import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:worker_manager/scheduler.dart';
import 'package:worker_manager/task.dart';
import 'package:worker_manager/thread.dart';

enum WorkPriority { high, low }
enum Policy { fifo } //todo: add _scheduler

abstract class Executor {
  Future<void> warmUp();

  Stream<O> addTask<I, O>({@required Task<O> task, WorkPriority priority = WorkPriority.high});

  void removeTask({@required Task task});

  void stop();

  factory Executor({int threadPoolSize = 1}) => _WorkerManager(threadPoolSize: threadPoolSize);

  factory Executor.fake() => _FakeWorker();

  factory Executor.fifo() => _WorkerManager(threadPoolSize: 1)..threadPoolSize = 1;
}

class _WorkerManager implements Executor {
  int threadPoolSize;
  final _scheduler = Scheduler();

  static final _WorkerManager _manager = _WorkerManager._internal();

  factory _WorkerManager({threadPoolSize = 1}) {
    if (_manager.threadPoolSize == null) {
      _manager.threadPoolSize = threadPoolSize;
      for (int i = 0; i < _manager.threadPoolSize; i++) {
        _manager._scheduler.threads.add(Thread());
      }
    }
    return _manager;
  }

  _WorkerManager._internal();

  @override
  Future<void> warmUp() async =>
      await Future.wait(_scheduler.threads.map((thread) => thread.initPortConnection()));

  @override
  Stream<O> addTask<I, O>({Task task, WorkPriority priority = WorkPriority.high}) {
    priority == WorkPriority.high
        ? _scheduler.queue.addFirst(task)
        : _scheduler.queue.addLast(task);
    if (_scheduler.queue.length == 1) _scheduler.manageQueue();
    return Stream.fromFuture(task.completer.future);
  }

  @override
  void removeTask({Task task}) {
    if (_scheduler.queue.contains(task)) _scheduler.queue.remove(task);
    final targetIsolate =
        _scheduler.threads.firstWhere((thread) => thread.taskId == task.id, orElse: () => null);
    if (targetIsolate != null) {
      targetIsolate.taskId = null;
      targetIsolate.isInitialized.future.then((_) {
        targetIsolate.cancel();
        _scheduler.threads.remove(targetIsolate);
        _scheduler.threads.add(Thread());
      });
    }
  }

  @override
  void stop() {
    _scheduler.threads.forEach((thread) {
      thread.cancel();
    });
    _scheduler.threads.clear();
    _scheduler.queue.clear();
  }
}

class _FakeWorker implements Executor {
  final _scheduler = Scheduler();

  @override
  Future<void> warmUp() {
    return null;
  }

  @override
  void removeTask({Task task}) {
    if (_scheduler.queue.contains(task)) _scheduler.queue.remove(task);
  }

  @override
  void stop() {}

  @override
  Stream<O> addTask<I, O>({Task<O> task, WorkPriority priority = WorkPriority.high}) {
    // TODO: implement addTask
    return null;
  }
}