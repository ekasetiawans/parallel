Running isolate easily.

## Features

Give more power to your app with multicore processing.

## Getting started

```dart
    void main() {
        // run core dedicated isolates.
        Parallel.initialize(
            numberOfIsolates: Platform.numberOfProcessor -1, // minus one used for allocating to main isolate.
            maxConcurrentPerIsolate: 100, // limit to 100 execution per isolate
            onInitialization: () {
                // register your dependency injection
                // for example using GetIt.I.register...
            },
        );

        runApp(MyApp());
    }
```

## Usage

Execute action in isolate.

```dart
final result = await Parallel.run((){
    // do your heavy task here.
});
```

Execute action in main isolate from worker isolate.

```dart
final result = await Parallel.run((){
    final data = await Parallel.runInMain((){
        // get your main data
    });

    print(data);
});
```
## Additional information

> **WARNING:**
> Since isolates are not sharing memory each other, you have to make sure the data that passed between isolates are not mutable.