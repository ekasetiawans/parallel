import 'dart:io';

import 'package:flutter/material.dart';
import 'package:parallel_dart/parallel_dart.dart';

void main() {
  Parallel.initialize(
    numberOfIsolates: Platform.numberOfProcessors - 1,
    maxConcurrentPerIsolate: 100,
    onInitialization: () {},
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parallel Dart',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Parallel Dart'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool isComputing = false;
  int number = 0;

  static void simulateHeavyComputing(int num) {
    for (var i = 0; i < num; i++) {
      // Literally do nothing here
    }

    print('Heavy Computing Is Done');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Counter : $number'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: isComputing
                  ? null
                  : () {
                      setState(() {
                        isComputing = true;
                      });
                      simulateHeavyComputing(1000000000000);
                      setState(() {
                        isComputing = false;
                      });
                    },
              child: const Text(
                  'Run heavy process without parallel - It Will Freeze'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: isComputing
                  ? null
                  : () async {
                      setState(() {
                        isComputing = true;
                      });

                      await Parallel.run(() async {
                        simulateHeavyComputing(1000000000000);

                        print('Heavy Computing Is Done');
                      });

                      setState(() {
                        isComputing = false;
                      });
                    },
              child: const Text('Run heavy process with parallel - Not Freeze'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            number++;
          });
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
