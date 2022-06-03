import 'dart:async';
import 'package:test/test.dart';
import 'package:worker_manager/worker_manager.dart';

Future<int> playPauseCheck(int attempts) async {
  var resultValue = 0;
  // final result = List.generate(attempts, (index) {
  //   return Future.delayed(Duration(milliseconds: 200), () {
  //     resultValue++;
  //   });
  // });
  // for (final element in result) {
  //   await element;
  // }
  await Future.delayed(Duration(milliseconds: 200));
  resultValue++;
  await Future.delayed(Duration(milliseconds: 200));
  resultValue++;
  await Future.delayed(Duration(milliseconds: 200));
  resultValue++;
  return resultValue;
}

Future<void> main() async {
  await Executor().warmUp(log: true);

  group('https://github.com/Renesanse/worker_manager/issues/54', () {
    test('No result after paused', () async {
      bool resultCame = false;
      final cPaused = Executor().execute(arg1: 3, fun1: playPauseCheck).thenNext((value) {
        resultCame = true;
      });
      await Future.delayed(Duration(milliseconds: 100));
      cPaused.pause();
      expect(resultCame, false);
      await Future.delayed(Duration(milliseconds: 2000));
      expect(resultCame, false);
    });

    test('Result after paused', () async {
      bool resultCame = false;
      final cPaused = Executor().execute(arg1: 3, fun1: playPauseCheck).thenNext((value) {
        resultCame = true;
      });
      await Future.delayed(Duration(milliseconds: 100));
      cPaused.pause();
      expect(resultCame, false);
      await Future.delayed(Duration(milliseconds: 100));
      cPaused.resume();
      await Future.delayed(Duration(milliseconds: 1000));
      expect(resultCame, true);
    });

    test('Kill paused cancelable', () async {
      var resultKill = 0;
      final c2 = Executor().execute(arg1: 3, fun1: playPauseCheck).thenNext((value) {
        resultKill++;
      }, (error) {
        expect(CanceledError, error.runtimeType);
      });
      await Future.delayed(Duration(milliseconds: 200));
      expect(resultKill, 0);
      c2.pause();
      await Future.delayed(Duration(milliseconds: 200));
      c2.cancel();
      await Future.delayed(Duration(milliseconds: 1000));
      expect(resultKill, 0);
    });

    test('Pause and resume merged', () async {
      var resultMerged = 0;
      final cm = Cancelable.mergeAll(List.generate(3, (index) {
        return Executor().execute(arg1: 3, fun1: playPauseCheck).thenNext((value) {
          resultMerged++;
        });
      }));
      await Future.delayed(Duration(milliseconds: 200));
      expect(resultMerged, 0);
      cm.pause();
      await Future.delayed(Duration(milliseconds: 1000));
      cm.resume();
      await Future.delayed(Duration(milliseconds: 1000));
      expect(resultMerged, 3);
    });

    test('Kill paused merged', () async {
      var resultMerged = 0;
      final cm = Cancelable.mergeAll(List.generate(3, (index) {
        return Executor().execute(arg1: 3, fun1: playPauseCheck).thenNext((value) {
          resultMerged++;
        });
      })).thenNext(null, (error) => expect(error.runtimeType, CanceledError));
      await Future.delayed(Duration(milliseconds: 200));
      expect(resultMerged, 0);
      cm.pause();
      await Future.delayed(Duration(milliseconds: 1500));
      cm.cancel();
      await Future.delayed(Duration(milliseconds: 1000));
      expect(resultMerged, 0);
    });

    test('Pool pause', () async {
      var resultKill = 0;
      final c2 = Executor().execute(arg1: 3, fun1: playPauseCheck).thenNext((value) {
        resultKill++;
      });
      await Future.delayed(Duration(milliseconds: 200));
      expect(resultKill, 0);
      Executor().pausePool();
      await Future.delayed(Duration(milliseconds: 2000));
      //double check
      expect(resultKill, 0);
      Executor().resumePool();
      await c2;
      expect(resultKill, 1);
    });
  });

  test('https://github.com/Renesanse/worker_manager/issues/53', () async {
    var result = 0;
    final cancelable = Cancelable.mergeAll(List.generate(
        10,
        (_) => Executor().execute(arg1: 36, fun1: fib).next(onValue: (_) {
              print(_);
              return _;
            }))).next(
        onError: (_) {
          print("Error");
        },
        onValue: (v) => result = v.fold(0, (a, b) => a + b));
    await Future.delayed(Duration(milliseconds: 100));
    cancelable.cancel();
    expect(result, 0);
  });

  test('https://github.com/Renesanse/worker_manager/issues/14', () async {
    var results = 0;
    Future<void> increment(String name, int n) async {
      await Executor().execute(arg1: name, arg2: n, fun2: isolateTask).next(onValue: (value) {
        results++;
      });
    }

    await increment('fn1', 1);
    await increment('fn2', 2);
    await increment('fn3', 3);
    await increment('fn4', 4);
    await increment('fn5', 5);
    await increment('fn6', 6);
    await increment('fn7', 7);
    await increment('fn8', 8);
    await increment('fn9', 9);
    await increment('fn10', 10);
    await increment('fn11', 11);
    await increment('fn12', 12);
    await increment('fn13', 13);
    expect(results == 13, true);
  });

  test('chaining', () async {
    int? r;
    await Executor().execute(arg1: 40, fun1: fib).next(onValue: (value) async {
      return value + 1;
    }).next(onValue: (value) async {
      await Future.delayed(oneSec);
      return value + 1;
    }).next(onValue: (value) async {
      await Future.delayed(oneSec);
      return value + 1;
    }).next(onValue: (v) {
      r = v;
    });
    expect(r, 102334158);
  });

  // test('onError', () async {
  //   Cancelable<int?>? c1;
  //   Future.delayed(oneSec * 0.1, () {
  //     c1!.cancel();
  //   });
  //
  //   await (c1 = Executor().execute(arg1: 40, fun1: fib).next(onValue: (value) {
  //     print(value);
  //     return value;
  //   }, onError: (e) {
  //     print(e);
  //   }));
  //   print("finish");
  // });

  test('important stress test with first isolate run and cancel', () async {
    Cancelable<void>? c1;
    Future.delayed(oneSec * 0.1, () {
      c1?.cancel();
    });

    c1 = Executor().execute(arg1: 40, fun1: fib).next(onValue: (value) {
      print(value);
      // return value;
    }, onError: (e) {
      print(e);
    });
    await c1;
    print("finish");

    final results = <int>[];
    for (var c = 0; c < 3; c++) {
      await Executor().execute(arg1: 38, fun1: fib).next(onValue: (value) {
        results.add(value);
        print(value);
      });
    }
    expect(results.length, 3);
  });

  // test('stress adding, canceling', () async {
  //   final results = <int>[];
  //   final errors = <Object>[];
  //   Cancelable<void> lastTask;
  //   for (var c = 0; c < 100; c++) {
  //     lastTask = Executor().execute(arg1: 38, fun1: fib).next(onValue: (value) {
  //       results.add(value);
  //     }, onError: (Object e) {
  //       errors.add(e);
  //     });
  //     lastTask.cancel();
  //   }
  //   expect(errors.length, 100);
  // });

  // test('stress adding, canceling with token', () async {
  //   final results = <int>[];
  //   final errors = <Object>[];
  //   for (var c = 0; c < 100; c++) {
  //     final cancelationTokenSource = CancelTokenSource();
  //     Executor().execute(arg1: 38, fun1: fib).next(onValue: (value) {
  //       results.add(value);
  //     }, onError: (Object e) {
  //       errors.add(e);
  //     }).withToken(cancelationTokenSource.token);
  //     cancelationTokenSource.cancel();
  //   }
  //   expect(errors.length, 100);
  // });

  // test('test fromFunction cancelationToken', () async {
  //   final results = <int>[];
  //   final errors = <Object>[];
  //
  //   final cancelable = Cancelable.fromFunction((token) async {
  //     try {
  //       final res1 = await Executor().execute(arg1: '2x2', arg2: 2, fun2: isolateTask).withToken(token);
  //       results.add(res1);
  //       final res2 = await Executor().execute(arg1: '4x2', arg2: 4, fun2: isolateTask).withToken(token);
  //       results.add(res2);
  //       final res3 = await Executor().execute(arg1: '8x2', arg2: 8, fun2: isolateTask).withToken(token);
  //       results.add(res3);
  //       final res4 = await Executor().execute(arg1: '16x2', arg2: 16, fun2: isolateTask).withToken(token);
  //       results.add(res4);
  //     } catch (e) {
  //       errors.add(e);
  //     }
  //   });
  //
  //   await Future.delayed(const Duration(milliseconds: 2100));
  //   expect(results.length, 2); // 2 computations should be compeleted after 2s
  //   cancelable.cancel();
  //   // wait to be sure that others computations were cancelled succesfully and results still the same
  //   await Future.delayed(const Duration(microseconds: 2500));
  //   expect(results.length, 2);
  //   expect(errors.length, 1);
  //   expect(errors[0], isA<CanceledError>());
  // });

  test('thx to null safety...', () async {
    final c = Completer<int?>();
    c.complete();
  });

  test('magic', () async {
    final c = doSomeMagicTrick();
    final result = await c.next(onValue: (v) {
      return v;
    });
    expect(result, 25);
  });

  test('isolatePool - should return the isolate back to pool on error', () async {
    var completedTasks = 0;
    for (int i = 0; i < 15; i++) {
      try {
        await Executor().execute(arg1: 'test', fun1: isolateTaskError);
      } catch (e) {
        // print(e);
      } finally {
        // print('completed task #$i');
        completedTasks++;
      }
    }
    expect(completedTasks, 15);
  });

  test("Test all errors", () async {
    var result = 0;
    for (var i = 0; i < 100; i++) {
      await Executor().execute(fun1: error, arg1: "Error").next(onError: (e) {
        result++;
      });
    }
    expect(result, 100);
  });

  test('onError chaining test', () async {
    int counter = 0;
    await Cancelable.fromFuture(Future.error(1)).next(onError: (value) {
      counter++;
      return Cancelable.fromFuture(Future.value(2));
    }).next(onValue: (value) {
      counter++;
      return Cancelable.fromFuture(Future.value(2));
    });
    expect(counter, 2);
  });
}

Cancelable<int?> doSomeMagicTrick() {
  return Cancelable.fromFuture(Future.delayed(const Duration(seconds: 1), () => 5))
      .next(onValue: (v) => v * 5);
}

Cancelable<void> nextTest() {
  return Executor().execute(arg1: 40, fun1: fib).next(onValue: (v) {
    print('returns nothing, but $v still');
  });
}

int fib(int n) {
  if (n < 2) {
    return n;
  }
  return fib(n - 2) + fib(n - 1);
}

Future<int> isolateTask(String name, int value) async {
  print('run isolateTask $name');
  await Future.delayed(const Duration(milliseconds: 1));
  return value * 2;
}

Future<int> isolateTaskError(String name) {
  throw Exception('Exception: my custom test exception');
}

void error(String text) {
  throw text;
}

const oneSec = Duration(seconds: 1);
