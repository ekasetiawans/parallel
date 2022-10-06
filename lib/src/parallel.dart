// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:isolate';

enum TaskEvent {
  added,
  processed,
  completed,
}

class Parallel {
  static bool _isMainIsolate = true;
  static bool get isMainIsolate => _isMainIsolate;

  static SendPort? _mainSendPort;
  static final Map<int, Completer> _mainCompleter = {};

  static Future<T> runInMain<T>(FutureOr<T> Function() fn) async {
    if (Parallel.isMainIsolate) {
      return fn();
    }

    final task = _TaskMessenger(arg: fn, id: _messengerId++);
    final completer = Completer<T>();
    _mainCompleter[task.id] = completer;
    _mainSendPort?.send(task);
    return completer.future;
  }

  final int numberOfIsolates;
  final int maxConcurrentPerIsolate;
  final StreamController<TaskEvent> _controller = StreamController.broadcast();
  Stream<TaskEvent> get eventStream => _controller.stream;
  final FutureOr<void> Function()? onInitialization;

  static Future<void> initialize({
    required int numberOfIsolates,
    int maxConcurrentPerIsolate = 10,
    FutureOr<void> Function()? onInitialization,
  }) async {
    if (_instance != null) {
      _instance!.dispose();
    }

    _instance = Parallel._(
      numberOfIsolates: numberOfIsolates,
      maxConcurrentPerIsolate: maxConcurrentPerIsolate,
      onInitialization: onInitialization,
    );
  }

  static Parallel? _instance;
  factory Parallel() =>
      _instance == null ? throw 'Call Parallel.initialize first' : _instance!;

  Parallel._({
    required this.numberOfIsolates,
    this.maxConcurrentPerIsolate = 10,
    this.onInitialization,
  }) {
    for (int i = 0; i < numberOfIsolates; i++) {
      _runner.add(
        _TaskRunner(
          id: i,
          onInitialization: onInitialization,
          parallel: this,
        ),
      );
    }
  }

  void dispose() {
    _controller.close();
    for (var runner in _runner) {
      runner.dispose();
    }
  }

  int _processCounter = 0;
  Future<void> _check() async {
    if (_tasks.isNotEmpty) {
      _runner.sort((a, b) => a.processCount.compareTo(b.processCount));
      final runner = _runner.first;

      if (runner.processCount < maxConcurrentPerIsolate) {
        final task = _tasks.removeAt(0);
        _processingTasks.add(task);
        _controller.sink.add(TaskEvent.processed);
        runner.run(task).then((value) {
          final completer = _completers.remove(task._id);
          completer?.complete(value);
        }).onError((error, stackTrace) {
          final completer = _completers.remove(task._id);
          completer?.completeError(error!, stackTrace);
        }).whenComplete(() {
          _processingTasks.remove(task);
          _check();
        });

        _processCounter++;
        if (_processCounter == numberOfIsolates) {
          _processCounter = 0;
        }

        _check();
      }
    } else {
      if (_processingTasks.isEmpty) {
        _controller.sink.add(TaskEvent.completed);
      }
    }
  }

  final List<_TaskRunner> _runner = [];
  final List<_ParallelTask> _tasks = [];
  final List<_ParallelTask> _processingTasks = [];
  final Map<int, Completer> _completers = {};

  static Future<T> run<T>(Future<T> Function() fn) async {
    if (!Parallel.isMainIsolate) {
      return fn();
    }

    return Parallel()._execute(_ParallelDelegate<T>(callback: fn));
  }

  Future<T> _execute<T>(_ParallelTask<T> task) {
    final completer = Completer<T>();
    _completers[task._id] = completer;
    _tasks.add(task);
    _controller.sink.add(TaskEvent.added);
    _check();

    return completer.future;
  }
}

class _TaskRunner {
  final Parallel parallel;
  final int id;
  final FutureOr<void> Function()? onInitialization;
  Isolate? isolate;
  StreamSubscription? subscription;

  _TaskRunner({
    required this.id,
    this.onInitialization,
    required this.parallel,
  }) {
    _createIsolate().then((value) {
      _sendPort.complete(value);
    });
  }

  void dispose() {
    subscription?.cancel();
    _sendPort.future.then((value) {
      value.send(_Terminate());
    });
  }

  Future<SendPort> _createIsolate() async {
    final receivePort = ReceivePort();

    final Completer<SendPort> sendPortCompleter = Completer();
    subscription = receivePort.listen((message) async {
      if (message is SendPort) {
        if (onInitialization != null) {
          message.send(onInitialization);
        }

        sendPortCompleter.complete(message);
        return;
      }

      if (message is _TaskMessenger) {
        if (message.arg is Function) {
          final f = message.arg as FutureOr Function();
          try {
            final result = await f();
            final port = await sendPortCompleter.future;
            port.send(
              _TaskMessenger(
                arg: result,
                id: message.id,
              ),
            );
          } catch (e) {
            final port = await sendPortCompleter.future;
            port.send(
              _TaskMessenger(
                id: message.id,
                arg: _TaskError(
                  id: message.id,
                  error: e,
                ),
              ),
            );
          }
        }
      }

      if (message is _TaskResult) {
        final queue = _tasks.remove(message.id);
        queue?.complete(message.value);
        return;
      }

      if (message is _TaskError) {
        final queue = _tasks.remove(message.id);
        queue?.completeError(message.error);
        return;
      }
    });

    isolate = await Isolate.spawn(
      _isolateEntrypoint,
      receivePort.sendPort,
      debugName: 'CPU#$id',
    );

    return sendPortCompleter.future;
  }

  static Future<void> _isolateEntrypoint<T>(SendPort sendPort) async {
    Parallel._mainSendPort = sendPort;
    Parallel._isMainIsolate = false;

    final port = ReceivePort();
    sendPort.send(port.sendPort);

    port.listen(
      (message) async {
        try {
          if (message is Function) {
            final onInitialization = message as FutureOr<void> Function();
            await onInitialization();
            return;
          }

          if (message is _TaskMessenger) {
            final completer = Parallel._mainCompleter.remove(message.id);
            if (message.arg is _TaskError) {
              completer?.completeError((message.arg as _TaskError).error);
            } else {
              completer?.complete(message.arg);
            }
          }

          if (message is _ParallelTask) {
            message.run().then((value) {
              sendPort.send(_TaskResult(
                value: value,
                id: message._id,
              ));
            }).onError((error, stackTrace) {
              sendPort.send(_TaskError(
                error: error!,
                id: message._id,
              ));
            });
          }

          if (message is _Terminate) {
            Isolate.exit();
          }
        } catch (e, s) {
          print(s);
        }
      },
    );
  }

  final Completer<SendPort> _sendPort = Completer();

  final Map<int, Completer> _tasks = {};
  int get processCount => _tasks.length;

  Future<T> run<T>(_ParallelTask<T> task) async {
    final completer = Completer<T>();
    _tasks[task._id] = completer;
    final sendPort = await _sendPort.future;
    sendPort.send(task);
    return completer.future;
  }
}

class _Terminate {}

class _TaskError {
  final int id;
  final Object error;
  const _TaskError({
    required this.id,
    required this.error,
  });
}

class _TaskResult {
  final int id;
  final Object? value;
  const _TaskResult({
    required this.id,
    this.value,
  });
}

int _taskIds = 0;

abstract class _ParallelTask<T> {
  final int _id = _taskIds++;
  Future<T> run();
}

int _messengerId = 0;

class _TaskMessenger {
  final int id;
  final dynamic arg;
  _TaskMessenger({
    required this.id,
    required this.arg,
  });
}

class _ParallelDelegate<T> extends _ParallelTask<T> {
  Future<T> Function() callback;
  _ParallelDelegate({
    required this.callback,
  });

  @override
  Future<T> run() {
    return callback();
  }
}
