#   iOS知识点总结

## 一、runloop

### 1、概念

**概念：runloop实际上就是一个对象，它提供了一种机制，能够让线程随时随地处理任务而不退出。**

### 2、和线程的关系

和线程一一对应，其关系保存在一个全局的字典里，key为线程（pthread_t），value为runloop（CFRunLoopRef）。

主线程的runloop系统自动创建。子线程中的runloop在第一次获取的时候创建，当线程退出时，runloop销毁。

**子线程中默认没有runLoop，除非主动去获取**

```objective-c
例：
//不会执行test
dispatch_async(dispatch_get_global_queue(0,0),^{
    [self performSelector:@selector(test) withObject:nil afterDelay:1];
});

修正后：
//会执行test方法
dispatch_async(dispatch_get_global_queue(0,0),^{
        [self performSelector:@selector(test) withObject:nil afterDelay:1];
        
        [[NSRunLoop currentRunLoop] addPort:[[NSPort alloc] init] forMode:NSDefaultRunLoopMode];
        [[NSRunLoop currentRunLoop] run];
});  

- (void)test{
   NSLog(@"test");
}
```



### 3、runloop的接口

在CoreFoundation里有五个类：

- CFRunLoopRef
- CFRunLoopModeRef
- CFRunLoopSourceRef
- CFRunLoopTimerRef
- CFRunLoopObserverRef

他们的关系如下

![RunLoop](/Users/wangjl/Downloads/iOS知识点总结/image/RunLoop.png)

#### 1、CFRunLoopModeRef

每个runloop包含多个mode，每个mode又包含多个Source/Observer/Timer。每次调用runloop的主函数时，只能指定一个mode，这个mode被称为CurrentMode。如果需要切换mode，只能退出runloop，再重新指定一个Mode进入。这样做是为了分割开不同组的Source/Observer/Timer，让其互不影响。

**系统默认注册5个mode：**

- kCFRunLoopDefaultMode:app默认Mode，通常主线程在这个Mode下工作
- UITrackingRunLoopMode:界面滑动Mode，用于scrollView追踪触摸滑动，保证滑动不受其他Mode影响。
- kCFRunLoopCommonModes:占位Mode，不是一个真正的Mode
- NSRunLoopCommonModes:NSDefaultRunLoopMode + UITrackingRunLoopMode。（**常用场景：NSTimer想要在滑动时也执行，需要将NSTimer加入到该Mode中**）
- UIInitializationRunLoopMode：刚启动app时进入的Mode，启动完成后不再使用
- GSEventRunLoopMode：接收系统事件的内部Mode，一般用不到。

**runLoop和mode的内部结构**:

```objective-c
struct __CFRunLoopMode {
    CFStringRef _name;            // Mode Name, 例如 @"kCFRunLoopDefaultMode"
    CFMutableSetRef _sources0;    // Set
    CFMutableSetRef _sources1;    // Set
    CFMutableArrayRef _observers; // Array
    CFMutableArrayRef _timers;    // Array
    ...
};
 
struct __CFRunLoop {
    CFMutableSetRef _commonModes;     // Set
    CFMutableSetRef _commonModeItems; // Set
    CFRunLoopModeRef _currentMode;    // Current Runloop Mode
    CFMutableSetRef _modes;           // Set
    ...
};
```

#### 2、CFRunLoopSourceRef

**是事件产生的地方。Source有两个版本：Source0 和 Source1。**

- Source0 只包含了一个回调（函数指针），它并不能主动触发事件。使用时，你需要先调用 CFRunLoopSourceSignal(source)，将这个 Source 标记为待处理，然后手动调用 CFRunLoopWakeUp(runloop) 来唤醒 RunLoop，让其处理这个事件。
- Source1 包含了一个 mach_port 和一个回调（函数指针），被用于通过内核和其他线程相互发送消息。这种 Source 能主动唤醒 RunLoop 的线程。

#### 3、CFRunLoopTimerRef

**是基于时间的触发器，它和 NSTimer 是toll-free bridged 的，可以混用。其包含一个时间长度和一个回调（函数指针）。当其加入到 RunLoop 时，RunLoop会注册对应的时间点，当时间点到时，RunLoop会被唤醒以执行那个回调。**

#### 4、CFRunLoopObserverRef

**观察者，每个 Observer 都包含了一个回调，当 RunLoop 的状态发生变化时，观察者就能通过回调接受到这个变化。可以观测的时间点有以下几个：**

```objective-c
typedef CF_OPTIONS(CFOptionFlags, CFRunLoopActivity) {
    kCFRunLoopEntry         = (1UL << 0), // 即将进入Loop
    kCFRunLoopBeforeTimers  = (1UL << 1), // 即将处理 Timer
    kCFRunLoopBeforeSources = (1UL << 2), // 即将处理 Source
    kCFRunLoopBeforeWaiting = (1UL << 5), // 即将进入休眠
    kCFRunLoopAfterWaiting  = (1UL << 6), // 刚从休眠中唤醒
    kCFRunLoopExit          = (1UL << 7), // 即将退出Loop
};
```

上面的 Source/Timer/Observer 被统称为 mode item，一个 item 可以被同时加入多个 mode。但一个 item 被重复加入同一个 mode 时是不会有效果的。如果一个 mode 中一个 item 都没有，则 RunLoop 会直接退出，不进入循环。

### 4、实例：

#### 1、检测线上界面卡顿

```objectivec
@property (nonatomic,strong) dispatch_semaphore_t semaphore;
@property (nonatomic,assign) CFRunLoopActivity activity;
@property (nonatomic,assign) NSInteger timeoutCount;

// 就是runloop有一个状态改变 就记录一下
static void runLoopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info) {
    // 记录状态值
    self.activity = activity;
    // 发送信号
    dispatch_semaphore_t semaphore = self.semaphore;
    long st = dispatch_semaphore_signal(semaphore);
}

// 开始监听
- (void)startMonitor {
    // 创建信号
    self.semaphore = dispatch_semaphore_create(0);
    self.timeoutCount = 0;
  
    // 注册RunLoop状态观察
    CFRunLoopObserverContext context = {0,(__bridge void*)self,NULL,NULL};
    //创建Run loop observer对象
    //第一个参数用于分配observer对象的内存
    //第二个参数用以设置observer所要关注的事件，详见回调函数myRunLoopObserver中注释
    //第三个参数用于标识该observer是在第一次进入run loop时执行还是每次进入run loop处理时均执行
    //第四个参数用于设置该observer的优先级
    //第五个参数用于设置该observer的回调函数
    //第六个参数用于设置该observer的运行环境
    CFRunLoopObserverRef observer = CFRunLoopObserverCreate(kCFAllocatorDefault,
                                       kCFRunLoopAllActivities,
                                       YES,
                                       0,
                                       &runLoopObserverCallBack,
                                       &context);
    CFRunLoopAddObserver(CFRunLoopGetMain(), observer, kCFRunLoopCommonModes);
    
    // 在子线程监控时长
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        while (YES) {// 有信号的话 就查询当前runloop的状态
            // 假定连续5次超时50ms认为卡顿(当然也包含了单次超时250ms)
            // 因为下面 runloop 状态改变回调方法runLoopObserverCallBack中会将信号量递增 1,所以每次 runloop 状态改变后,下面的语句都会执行一次
            // dispatch_semaphore_wait:Returns zero on success, or non-zero if the timeout occurred.
            long st = dispatch_semaphore_wait(self.semaphore, dispatch_time(DISPATCH_TIME_NOW, 50*NSEC_PER_MSEC));

            if (st != 0) {  // 信号量超时了 - 即 runloop 的状态长时间没有发生变更,长期处于某一个状态下
                  // kCFRunLoopBeforeSources - 即将处理source 
                  // kCFRunLoopAfterWaiting - 刚从休眠中唤醒
                  // 获取kCFRunLoopBeforeSources到kCFRunLoopBeforeWaiting再到kCFRunLoopAfterWaiting的状态就可以知道是否有卡顿的情况。
                  // kCFRunLoopBeforeSources:停留在这个状态,表示在做很多事情
                  if (self.activity == kCFRunLoopBeforeSources || self.activity == kCFRunLoopAfterWaiting) {// 发生卡顿,记录卡顿次数
                    self.timeoutCount ++;  
                    if (self.timeoutCount < 5) {
                          continue;   // 不足 5 次,直接 continue 当次循环,不将timeoutCount置为0
                      }
                      //记录卡顿信息
                  }
              }

              self.timeoutCount = 0;
        }
    });
}
```

#### 2、NSTimer

#### 3、performselector

#### 4、自动释放池

## 二、多线程

**程序中有多条线程在执行任务。**

### 1、进程和线程

**进程：**

1. 在iOS 中 一个进程就是一个正在运行的一个应用程序; 比如 QQ.app ，而且一个app只能有一个进程 不像安卓支持多个进程。
2. 每一个进度都是独立的，每一个进程均在专门且手保护的内存空间内;
3. iOS中是一个非常封闭的系统，每一个App（一个进程）都有自己独特的内存和磁盘空间，别的App（进程）是不允许访问的（越狱不在讨论范围）；
4. 进程 是系统资源分配和调度的一个独立单位，简单的理解就是用来帮程序占据一定的存储空间等的资源。进程拥有自己独立的位置空间，在没有经过进程本身允许的情况下，其他进程不能访问改进程的地址空间

**线程：**

1. 线程是CPU调度的最小单元；
2. 线程的作用：执行app的代码；
3. 一个进程（App）至少有一个线程，这个进程叫做主线程；

### 2、ios中常见的多线程方案

一共有四种方案：**1.pthread、2.NSThread、3.GCD、4.NSOperation。后面三种的底层都是pthread。**

![多线程方案](/Users/wangjl/Downloads/iOS知识点总结/image/多线程方案.png)

#### 1、pthread

#### 2、NSThread

**NSThread创建的三种方式**

```objective-c
//方式一
NSThread *t1 = [[NSThread alloc] initWithTarget:self selector:@selector(run:) object:@"abc"];
[t1 start];

//方式二
[NSThread detachNewThreadSelector:@selector(run:) toTarget:self withObject:@"分离子线程"];

//方式三
[self performSelector:@selector(run:) withObject:@"开启后台线程"];
```



#### 3、GCD

使用sync往主队列中添加任务，会造成**死锁**（卡住当前的串行队列）

```objective-c
例1：
  dispatch_queue_t serQueue = dispatch_queue_create("com.Damon.GCDSerial", DISPATCH_QUEUE_SERIAL);

dispatch_async(serQueue, ^{

    NSLog(@"2");

    dispatch_sync(serQueue, ^ {//在当前的串行队列里添加此处造成死锁
        NSLog(@"3");
    });

    NSLog(@"4");
});

例2：
dispatch_queue_t mainQueue = dispatch_get_main_queue();
dispatch_sync(mainQueue,^{//会造成死锁

});
```

**子线程中默认没有runLoop，除非主动去获取**

```objective-c
例：
- (void)test{
   NSLog(@"test");
}

//不会执行test
dispatch_async(dispatch_get_global_queue(0,0),^{
    [self performSelector:@selector(test) withObject:nil afterDelay:1];
});


修正后：
//会执行test方法
dispatch_async(dispatch_get_global_queue(0,0),^{
        [self performSelector:@selector(test) withObject:nil afterDelay:1];
        
        [[NSRunLoop currentRunLoop] addPort:[[NSPort alloc] init] forMode:NSDefaultRunLoopMode];
        [[NSRunLoop currentRunLoop] run];
});  
```

 

#### 4、NSOperation

基于GCD（底层是GCD）

#### 注意：解决线程的安全问题方案：

1、使用线程同步

2、加锁



### 3、异步/同步、并发/串行

**异步/同步：**

异步：开启新线程。在新线程中执行任务。

同步：不开线程。只在当前线程中执行任务，立马去执行当前线程中的任务。

**线程同步方案性能比较：**

**os_unfair_lock > OSSpinLock > dispatch_semaphore > pthread_mutex > dispatch_queue(DISPATCH_QUEUE_SERIAL) > NSLock > NSCondition > pthread_mutex(recursive) > NSRecursiveLock > NSConditionLock > @synchronized** 

**队列：存放任务的结构**

并发队列：可多个任务并发执行，需要开启新线程执行多个任务。只在异步函数下有效。

串行队列：只能执行完一个任务再执行下一个任务。

主队列：主队列的任务只在主线程中执行。特点：FIFO，先进先出；主队列如果发现主线程中有任务在执行，那么它会暂停主队列中的任务，等主线程空闲后再执行。

```objective-c
//异步并发：可能开多个线程
dispatch_queue_t asyncConcurrentQueue = dispatch_queue_create("com.test.wjlAsyncCon", DISPATCH_QUEUE_CONCURRENT);
for (int i = 0; i< 100 ;i++) {
    dispatch_async(asyncConcurrentQueue,^{
        NSLog(@"异步并行--i:%d 当前线程：%@",i,[NSThread currentThread]);
    });
}
    
//异步串行：只开一个线程
dispatch_queue_t asyncSeriQueue = dispatch_queue_create("com.test.wjlAsyncSerial", DISPATCH_QUEUE_SERIAL);
for (int i = 0; i< 100 ;i++) {
    dispatch_async(asyncSeriQueue,^{
        NSLog(@"异步串行--i:%d 当前线程：%@",i,[NSThread currentThread]);
    });
}

//同步并发：不开线程 串行执行
dispatch_queue_t syncSeriCon = dispatch_queue_create("com.test.wjlSyncCon", DISPATCH_QUEUE_CONCURRENT);
for (int i = 0; i< 100 ;i++) {
  dispatch_sync(syncSeriCon,^{
      NSLog(@"同步并行--i:%d 当前线程：%@",i,[NSThread currentThread]);
  });
}

//同步串行：不开线程 串行执行
dispatch_queue_t syncSeriQueue = dispatch_queue_create("com.test.wjlSyncSerial", DISPATCH_QUEUE_SERIAL);
for (int i = 0; i< 100 ;i++) {
    dispatch_sync(syncSeriQueue,^{
        NSLog(@"同步串行--i:%d 当前线程：%@",i,[NSThread currentThread]);
    });
}

//异步主队列：不开线程，在主线程中执行；等待当前主线程中所有任务执行完后再执行
dispatch_queue_t mainqueue = dispatch_get_main_queue();
for (int i = 0; i<100; i ++) {
    dispatch_async(mainqueue,^{
        NSLog(@"异步主队列-- i：%d 当前线程：%@",i,[NSThread currentThread]);
    });
}

//同步主队列：死锁；主队列发现当前主线程中有任务执行，那么主队列会暂停队列中的任务，等主线程空闲后再执行
dispatch_queue_t mainQueue = dispatch_get_main_queue();
for (int i = 0; i < 100; i ++) {
    dispatch_sync(mainQueue,^{
        NSLog(@"同步主队列--i：%d 当前线程：%@",i,[NSThread currentThread]);
    });
}
```

### 4、线程间通信

#### 1、NSThread

performSelectorOnMainThread:

performSelector:OnThread:

#### 2、GCD

主线程和子线程切换，例：子线程中请求接口，然后在主线程中刷新UI

```objective-c
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    // 1.子线程下载图片
    NSURL *url = [NSURL URLWithString:@"http://d.jpg"];
    NSData *data = [NSData dataWithContentsOfURL:url];
    UIImage *image = [UIImage imageWithData:data];

    // 2.回到主线程设置图片
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.button setImage:image forState:UIControlStateNormal];
    });
});
```

#### 3、NSOperationQueue实现

### 5、GCD

#### 1、group

```objective-c
dispatch_group_t group = dispatch_group_create();
    dispatch_group_async(group,dispatch_get_global_queue(0,0),^{
        for (int i = 0; i < 100; i ++) {
            NSLog(@"当前线程：%@，第%d次任务",[NSThread currentThread],i);
        }
    });

    dispatch_group_async(group,dispatch_get_global_queue(0,0),^{
        for (int i = 0; i < 100; i ++) {
            NSLog(@"当前线程：%@，第%d次任务",[NSThread currentThread],i);
        }
    });

    dispatch_group_notify(group,dispatch_get_main_queue(),^{
        NSLog(@"所有线程内任务执行完毕");
    });
```

### 6、线程锁

锁的性能对比（单线程）：最上面性能最高

![lock_benchmark](/Users/wangjl/Downloads/iOS知识点总结/image/线程锁性能对比.png)

#### 1、互斥锁

**概念：**如果共享数据已经有其他线程加锁了，线程会进入休眠状态等待。一旦被访问的资源被解锁，则等待资源的线程会被唤醒。这种处理方式就叫做互斥锁。（当上一个线程里的任务没有执行完毕的时候，那么下一个线程的任务会进入睡眠状态；当上一个任务执行完毕时，下一个线程会自动唤醒然后执行任务。）

##### 1、@synchronized 关键字加锁

使用方法：

```objective-c
@synchronized(这里添加一个OC对象，一般使用self) {
这里写要加锁的代码
}

例：
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

     @synchronized(self) {
         NSLog(@"需要线程同步的操作1 开始");
         sleep(3);
         NSLog(@"需要线程同步的操作1 结束");
     }
 });

 dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
     @synchronized(self) {
         NSLog(@"需要线程同步的操作2");
     }
 });

打印：
2021-10-21 14:50:43.184595+0800 DefaultDemo[8136:1488475] 需要线程同步的操作1 开始
2021-10-21 14:50:46.187374+0800 DefaultDemo[8136:1488475] 需要线程同步的操作1 结束
2021-10-21 14:50:46.188223+0800 DefaultDemo[8136:1488476] 需要线程同步的操作2
```

**优点：**

- 使用简单,不需要显式的创建锁对象，便可以实现锁的机制。

**缺点：**

- 性能差

**注意点：**

- 加锁的代码尽量少
- 添加的OC对象必须在多个线程中都是同一对象
- @synchronized块会隐式的添加一个异常处理例程来保护代码，该处理例程会在异常抛出的时候自动的释放互斥锁。所以如果不想让隐式的异常处理例程带来额外的开销，你可以考虑使用锁对象。

##### 2、NSLock 对象锁

底层是对pthread_mutex的封装。

```objective-c
//主线程中
NSLock *lock = [[NSLock alloc] init];

//线程1
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      [lock lock];
      NSLog(@"线程1");
      [lock unlock];
      NSLog(@"线程1解锁成功");
});

//线程2
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      [lock lock];
      NSLog(@"线程2");
      [lock unlock];
});

/*注意：
 *上面的代码会按照顺序去执行
 *但是如果有多于两个任务的话，就不能保证顺序执行，只能保证第一个任务会第一个执行，但是后面的代码不一定先执行哪一个
*/
打印：
2021-10-20 11:30:24.682966+0800 DefaultDemo[7390:1308115] 线程1
2021-10-20 11:30:26.688436+0800 DefaultDemo[7390:1308115] 线程1解锁成功
2021-10-20 11:30:26.688503+0800 DefaultDemo[7390:1308074] 线程2
```

**注意：**

- lock和unlock是成对存在的，连续使用lock()，会造成死锁。在Main线程死锁的话，程序直接卡死；若在子线程中死锁，并不会影响主线程。

  ```objective-c
  //主线程中，直接卡死
  NSLock *lock = [[NSLock alloc] init];
  [lock lock];
  [lock lock];
  NSLog(@"main");//不执行 直接卡死（多次调用[lock lock]）
  ```

  ```objective-c
  //线程 子线程死锁，但不影响主线程
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      [lock lock];
      [lock lock];
      NSLog(@"线程1");//不打印
      [lock unlock];
      NSLog(@"线程1解锁成功");//不打印
  });
  
  NSLog(@"main");//打印
  ```

  

- 由于NSLock不能多次调用`lock`的方法，因此除了NSLocking协议提供的方法外，还提供了`tryLock`和`lockBeforeDate`两个方法。

  ```objective-c
  tryLock试图获取一个锁，但是如果锁不可用的时候，它不会阻塞线程，相反，它只是返回NO。
  lockBeforeDate:方法试图获取一个锁，但是如果锁没有在规定的时间内被获得，它会让线程从阻塞状态变为非阻塞状态（或者返回NO）。
  
  ```

- 因此`NSLock`遇到递归等会重复调用`lock`的方法时，采用`tryLock`和`lockBeforeDate`时只能避免线程死锁的问题。但`NSLock`因为没有对实质问题进行处理因此在递归的情况下，使用对象锁仍然是不安全的。

##### 3、pthread_mutex 

**用法：1、初始化锁属性；2、初始化互斥锁；3、加锁、解锁；** **4、销毁mutex**

```objective-c
 __block pthread_mutex_t mutex;
 pthread_mutex_init(&mutex,NULL);

 dispatch_async(dispatch_get_global_queue(0,0),^{
      pthread_mutex_lock(&mutex);
      NSLog(@"任务1");
      sleep(3);
      pthread_mutex_unlock(&mutex);
 });

 dispatch_async(dispatch_get_global_queue(0,0),^{
      pthread_mutex_lock(&mutex);
      NSLog(@"任务2");
      pthread_mutex_unlock(&mutex);
 });

//销毁mutex
pthread_mutex_destroy(&muetx)
  
打印：
2021-10-22 15:59:42.683841+0800 DefaultDemo[8383:1611181] 任务1
2021-10-22 15:59:45.687680+0800 DefaultDemo[8383:1611175] 任务2

```

#### 2、spin lock 自旋锁

**概念：**线程反复检查锁变量是否可用，一直占用cpu；由于线程在这一过程中保持执行，因此是一种忙等状态。一旦获取了自旋锁，线程会一直持有该锁，直至显式释放自旋锁。

获取、释放自旋锁，实际上是读写自旋锁存储内存或寄存器。因此这种读写操作必须是原子的（atomic）。

**优点：充分利用cpu资源**

**缺点：耗性能**

##### 1、OSSpinLock （不推荐使用）

需要导入头文件**<libkern/OSAtomic.h>**

不安全，被弃用。原因：具体来说，如果一个**低优先级**的线程获得锁并访问共享资源，这时一个**高优先级**的线程也尝试获得这个锁，**高优先级**会处于 spin lock 的忙等状态从而占用大量 CPU。此时**低优先级**线程无法与**高优先级**线程争夺 CPU 时间，从而导致任务迟迟完不成、无法释放 lock。

**os_unfair_lock**用于取代OSSpinLock，从iOS10开始支持。从底层看，等待os_unfair_lock锁的线程会处于休眠状态，并非忙等。（需要导入头文件：**<os/lock.h>**）

```objective-c
//初始化
os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
//尝试加锁
os_unfair_lock_trylock(&lock);//返回BOOL NO：已有人加锁，等待； YES：还未加锁，可以加锁
//加锁
os_unfair_lock_lock(&lock);
//解锁
os_unfair_lock_unlock(&lock);
```



**自旋锁互斥锁对比**

 ![自旋锁互斥锁对比](/Users/wangjl/Downloads/iOS知识点总结/image/自旋锁互斥锁对比.png)

#### 3、递归锁

**概念：允许同一个线程多次递归访问被锁资源，加锁和解锁必须成对出现，使得最终锁能够被解开，其它线程能够访问资源**.

因为研究对象锁（NSLock）时我们指出过`NSLock`最大的问题是处理递归问题时由于重复调用`lock`方法导致死锁，递归锁就是专门为了处理递归流程设计的。与对象锁一样递归锁遵循NSLocking协议，并实现了`tryLock`和`lockBeforeDate`两个方法。

##### 1、NSRecursiveLock

对pthread_mutex的一个封装。

```objective-c
// NSLock *lock = [[NSLock alloc] init];
NSRecursiveLock *recursiveLock = [[NSRecursiveLock alloc] init];

dispatch_async(dispatch_get_global_queue(0,0),^{

  testRecursiveLock = ^(int value){
      //[lock lock];//重复调用会造成死锁，所以只打印了value：5
      [recursiveLock lock];//重复调用不会造成死锁，会打印value：5--value：0、main

      NSLog(@"value:%d",value);
      if (value > 0) {
          value -- ;
          testRecursiveLock(value);
      }
      //[lock unlock];
      [recursiveLock unlock];
  };

  testRecursiveLock(5);
  NSLog(@"main");
});
```

##### 2、pthread_mutex 实现递归锁

```objective-c
__block pthread_mutex_t mutex;
pthread_mutexattr_t att;
pthread_mutexattr_settype(&att, PTHREAD_MUTEX_RECURSIVE);

pthread_mutex_init(&mutex,&att);

// 下面一段可以被同一个线程，在一个或多个方法中多次调用
pthread_mutex_lock(&mutex);
// TODO:
pthread_mutex_unlock(&mutex);

//销毁mutex
pthread_mutex_destroy(&muetx)
```



#### 4、信号量（dispatch_semaphore） 实现加锁

**dispatch_semaphore_create(value)**：创建信号量。value必须>=0，否则返回NULL。value是控制线程并发访问的最大数量。

**dispatch_semaphore_signal(semaphore)**：会让value+1，value>=0时，当前线程会被唤醒，执行队列中剩余的任务。

**dispatch_semaphore_wait(semaphore,timeout)**：会让value-1，value<0时，当前线程会进入睡眠状态（被锁住），被锁住多久，取决于timeout参数，DISPATCH_TIME_FOREVER表示无限期休眠。

```objective-c
dispathc_semaphore_t semaphore = dispatch_semaphore_create(0);

dispatch_async(dispatch_get_global_queue(0, 0),^{

    NSLog(@"1");

    sleep(3);
    dispatch_semaphore_signal(self.semaphore);
});

dispatch_async(dispatch_get_global_queue(0, 0),^{

   dispatch_semaphore_wait(self.semaphore,DISPATCH_TIME_FOREVER);
   NSLog(@"2");
});

打印：
2021-10-22 16:48:42.571397+0800 DefaultDemo[8462:1625383] 1
2021-10-22 16:48:45.577893+0800 DefaultDemo[8462:1625357] 2  //打印1之后3s才会打印2

```

#### 5、NSCondition/NSConditionLock 条件锁 

**可以实现任务的串行执行。**

```objective-c
NSConditionLock *conditionLock = [NSConditionLock alloc] initWithCondition:1];

dispatch_queue_t queue1 = dispatch_queue_create("com.DamonTest.queue1",DISPATCH_QUEUE_CONCURRENT);
dispatch_queue_t queue2 = dispatch_queue_create("com.DamonTest.queue2",DISPATCH_QUEUE_CONCURRENT);
dispatch_queue_t queue3 = dispatch_queue_create("com.DamonTest.queue3",DISPATCH_QUEUE_CONCURRENT);

dispatch_async(queue1,^{
  [conditionLock lock];
  NSLog(@"任务1");
  [conditionLock unlockWithCondition:2];
});

dispatch_async(queue2,^{
  [conditionLock lockWhenCondition:2];//当条件值为2的时候开始加锁，并执行下面代码
  NSLog(@"任务2");
  [conditionLock unlockWithCondition:3];
});

dispatch_async(queue1,^{
  [conditionLock lockWhenCondition:3];
   NSLog(@"任务3");
  [conditionLock unlock];
});

打印：//顺序执行任务1、任务2、任务3
2021-10-24 15:34:47.569859+0800 DefaultDemo[9260:1887088] conditon1
2021-10-24 15:34:47.570333+0800 DefaultDemo[9260:1887088] conditon2
2021-10-24 15:34:47.570559+0800 DefaultDemo[9260:1886516] conditon3
```

#### 6、dispatch_barrier_async 栅栏

只要有任务在栅栏里执行的时候，栅栏所在的队列里的其他任务就不会执行。

**注意：**

**传入的队列必须是自己手动通过dispatch_queue_create创建的并发队列；**

**如果传入的是串行队列或全局并发队列，那么它的效果同dispatch_async。**

**实现加锁**

```objective-c
dispatch_queue_t concurrentQueue = dispatch_queue_create("com.DamonTest.concurrent",DISPATCH_QUEUE_CONCURRENT);

dispatch_async(concurrentQueue,^{
    NSLog(@"1");
}); 

dispatch_async(concurrentQueue,^{
    NSLog(@"2");
    sleep(3);
});

dispatch_barrier_async(concurrentQueue,^{//也可以换成sync，换成sync后，
    NSLog(@"barrier");
});

//NSLog(@"若此处有主线程的方法：barrier是async,则不会等待barrier内的方法执行完毕就能打印；barrier是sync，则必须等待barrier里的任务执行完毕才能打印");

dispatch_async(concurrentQueue,^{
    NSLog(@"3");
});

打印：1、2、barrier、3
注意：上面的打印1和2的顺序是不确定的，但3肯定是最后打印
```

Dispatch_barrier_async也可以实现多读单写操作

```objective-c
//多读单写例：
@property (nonatomic, assign) dispatch_queue_t queue;

- (void)viewDidLoad{

  		self.queue = dispatch_queue_create("com.Damon.test",DISPATCH_QUEUE_CONCURRENT);

      for (int i = 0; i< 10; i ++){
            [self read];
            [self read];
            [self read];
            [self write];
      }
}

- (void)read{
  dispatch_async(self.queue,^{
			NSLog(@"read");//有可能在1s内连续打印
      sleep(1);
  });
}

- (void)write{
  dispatch_barrier_async(self.queue,^{
			NSLog(@"write");//只能每隔1s打印一次
  		sleep(1);
  });
}

```



#### 7、pthread_rwlock 读写锁

```objective-c
//初始化锁
pthread_rwlock_t lock;
pthread_rwlock_init(&lock,NULL);
//读-加锁
pthread_rwlock_rdlock(&lock);
//读-尝试加锁
pthread_rwlock_trylock(&lock);
//写-加锁
pthread_rwlock_wrlock(&lock);
//写-尝试加锁
pthread_rwlock_trywrlock(&lock);
//解锁
pthread_rwlock_unlock(&lock);
//销毁锁
pthread_rwlock_destroy(&lock);
```

**可以实现多读单写操作（同时满足以下三个条件）**

- 每次只能有一个线程在进行写的操作；
- 每次可以有多个线程进行读的操作
- 读的时候不能有写，写的时候不能有读

```objective-c
@property (nonatomic,assign) pthread_rwlock_t rwlock;

- (void)viewDidLoad{
  pthread_rwlock_init(&_rwlock, NULL);
    //记得要销毁 pthread_rwlock_destroy(&_rwlock)
    
    for (int i = 0; i < 10; i ++) {
        dispatch_async(dispatch_get_global_queue(0, 0),^{
            
            [self read];
            [self write];
        });
    }
}

- (void)read{
    pthread_rwlock_rdlock(&_rwlock);
    NSLog(@"read");//支持多次读取，而且读的时候不会有写的操作
    pthread_rwlock_unlock(&_rwlock);
}

- (void)write{
    pthread_rwlock_wrlock(&_rwlock);
    NSLog(@"write");//只能一次一次的写，而且写的时候不会有读的操作
    sleep(1);
    pthread_rwlock_unlock(&_rwlock);
}
```



## 三、Runtime （运行时）

概念：OC是一门动态性比较强的编程语言，允许许多操作推迟到运行时在进行，OC的动态性就是由Runtime去支撑的，Runtime是一套C语言的API，封装了很多动态性相关的函数，平时编写的OC代码，底层都转成了Runtime API进行调用

### 1、动态性

主要是将数据类型的确定由编译时，推迟到了运行时。这个问题其实浅涉及到两个概念，**运行时**和**多态**。简单来说，**运行时机制**使我们直到运
行时才去决定一个对象的类别，以及调用该类别对象指定方法。**多态**：不同对象以自己的方式响应相同的消息的能力叫做多态。

> 例子：假设生物类（life）都有一个相同的方法-eat;那人类属于生物，猪也属于生物，都继承了 life
> 后，实现各自的 eat，但是调用是我们只需调用各自的 eat 方法。也就是不同的
> 对象以自己的方式响应了相同的消息（响应了 eat 这个选择器）。因此也可以
> 说，运行时机制是多态的基础。



### 2、位运算

```objective-c
与运算
0000 0100       
&0001 0000
----------
0000 0000

或运算
 0000 0100
|0001 0000
----------
 0001 0100
 
 1<<0:表示1往左移0位，即 0000 0001，即十进制的1
 1<<1:表示1往左移1位，即 0000 0010，即十进制的2
 1<<2:表示1往左移2位，即 0000 0100，即十进制的4
```

一般做底层架构设计时，为了提高性能、节约资源，会将多个变量设计成一个char类型的变量，然后根据按位运算取对应的值。例如：

```objective-c
/*背景：
*我们需要一个变量来保存用户的tall、rich、handsome，三个变量都是BOOL类型
*/

//Mask：掩码，一般用来按位与（&）运算。
#define  WJLTallMask 0b00000001 
#define  WJLRichMask 0b00000010
#define  WJLHandsomeMask 0b00000100
//上面的宏定义也可以写成下面的方式
#define  WJLTallMask (1<<0)
#define  WJLRichMask (1<<1)
#define  WJLHandsomeMask (1<<2)
   
@interface
{
  char _tallRichHandsome;
}
@end
- (instancetype)init{
    if(self = [super init]){
				_tallRichHansome = 0b00000100;//我们定义：从左到右，第0位表示tall，第1位：rich，第2位：handsome。（此时的默认值tall、rich、handsome分别是0、0、1）
    }
}

- (BOOL)tall{
  /*
  *!!表示取两次反，并且转换为BOOL类型
  *例：假设此时的前置条件是_tallRichHansome为0b00000100(tall：0，rich：0，handsome：1)
  *_tallRichHansome & WJLTallMask的位运算结果为0b00000000，代表tall为0
  *也就是说此时的位运算结果为十进制为0，我们要转为BOOL类型，那么!(0)则代表YES，两次取反!!(0)则为NO
  *当然也可以强转BOOL类型:（BOOL)(_tallRichHansome & WJLTallMask)
  */
    return !!(_tallRichHansome & WJLTallMask)e
}

- (BOOL)rich{
     return !!(_tallRichHansome & WJLRichMask);
}

- (BOOL)handsome{
     return !!(_tallRichHansome & WJLHandsomeMask);
}

- (void)setTall:(BOOL)tall{
  	if(tall){
      /*YES
      * 用‘或’运算，其他位置不变，将最左边的一位变为1。如果最左侧一位为1，则1|1=1；如果最左侧为0，则0|1=1，所以用‘或’运算
      * 0b0000 0100
      *|0b0000 0001
      *-------------
      * 0b0000 0101
      */
       _tallRichHandsome |= WJLTallMask;//同_tallRichHandsome = _tallRichHandsome | WJLTallMask;
    }else{
      /*NO
      * 用‘与’运算，其他位置不变，将最左侧一位变为0。
      * 先对WJLTallMask取反变为0b11111110
      * 0b0000 0100
      *&0b1111 1110
      *-------------
      * 0b0000 0100
      */
      _tallRichHandsome &= ~WJLTallMask;//同_tallRichHandsome = _tallRichHandsome & (~WJLTallMask);
    }
}

- (void)setRich:(BOOL)rich{
			//计算方式同tall
      if(rich){
           _tallRichHandsome |= WJLRichMask;
      }else{
          _tallRichHandsome &= ~WJLRichMask;
      }
}

- (void)setHandsome:(BOOL)handsome{
			//计算方式同tall
      if(handsome){
           _tallRichHandsome |= WJLHandsomeMask;
      }else{
          _tallRichHandsome &= ~WJLHandsomeMask;
      }
}
```

### 3、位域

所谓"位域"是把一个字节中的二进位划分为几个不同的区域，并说明每个区域的位数。每个域有一个域名，允许在程序中按域名进行操作。这样就可以把几个不同的对象用一个字节的二进制位域来表示。

### 4、共用体

所有变量共用一块内存。

```objective-c
union{
		int a;//int类型 4字节
  	int b;//4字节
  	int c;//4字节
}
//上述a、b、c共用四个字节
  
 union{
		int a;//int类型 4字节
  	char b;//1字节
}
//上述a、b共用4个字节

/*
*oc源码里面共用体一般如下结构
*/
union isa_t{
  uintptr_t bits;//bits包含下面结构体里所有的变量数据
  struct{//struct单纯的为了可读性，用来表示isa里包含了哪几个变量数据
			uintptr_t nonpointer : 1;//其中“：”代表指定多少字节来存储该数据，结构体struct支持指定内存大小来存储数据
    	uintptr_t has_asoc : 1;
    	uintptr_t has_cxx_dtor : 1;
      uintptr_t shiftcls : 1;
    	uintptr_t magic : 1;
    	uintptr_t weakly_referenced : 1;
      uintptr_t deallocating : 1;
    	uintptr_t has_sidetable_rc : 1;
      uintptr_t extra_rc : 1;
  };
};

```

![位域](/Users/wangjl/Downloads/iOS知识点总结/image/位域.png)

### 5、class

![isa:superclas继承图](/Users/wangjl/Downloads/iOS知识点总结/image/isa以及superclas继承图.png)

![class内部结构](/Users/wangjl/Downloads/iOS知识点总结/image/class内部结构.png)

**isa**：等价于is kind of

- 实例对象的isa指向类对象
- 类对象的isa指针指向元类对象
- 元类对象的isa指针指向元类的基类

**cache**里利用散列表(哈希表）形式保存了调用过的方法，如此设计可以大大优化函数调用时间。

**class_ro_t**：readonly。存储了当前类在编译期就已经确定的属性、方法以及遵循的协议。

其中**methods**和**properties**和**protocols**都是二维数组，是可读可写的，即数组中也存在数组，数组中包含类的初始内容、分类内容。methods中存着**method_list_t**，**method_list_t**中存在**method_t**。这三个数组中的数据有一部分是从**class_ro_t**合并过来的。



#### method_t

method_t是对方法（函数）的封装

```objective-c
struct method_t{
  SEL name;//函数名
  const char *types;// 编码。包括返回值类型以及参数类型
  IMP imp;//函数指针
}
```

- **IMP**代表函数的具体实现

  ```objective-c
  typedef id _Nullable (*IMP)(id _Nonnull,SEL _Nonnull,....);
  ```

- **SEL**代表方法名（函数名），一般叫做选择器，底层结构和char *类似

```objective-c
1.可以通过@selector()和sel_registerName()获得；
2.可以通过sel_getName()和NSStringFromSelector()转成字符串；
3.不同类中名字的方法，所对应的方法选择器是相同的；
  typedef struct objc_selector *SEL;
```

- **type**包含了函数返回值、参数编码的字符串。

  type的组成结构为：返回值+参数1+参数2+...+参数n

  ```objective-c
  例子：现有方法如下
  - (int)test:(int)age height:(float)height;
  ios中函数的每个方法都隐藏了两个参数：id:(id)self _cmd:(SEL)_cmd，所以上述方法完整写法就是：
  - (int)test:(id)self _cmd:(SEL)_cmd age:(int)age height:(float)height;
  上面的方法type值即：i24@0:8i16f20 //其中i代表返回值为int类型；24代表方法参数共占24个字节;@代表参数类型为id，0代表内存从第0个字节开始计算；“：”代表参数为SEL，8代表内存从第8个字节开始计算；....
  iOS提供了一个叫作@encode的指令，可以将具体的类型表示为字符串编码
  ```

  ![type encoding](/Users/wangjl/Downloads/iOS知识点总结/image/type encoding.png)
  

#### cache_t 

**方法缓存，用来缓存已经调用过的方法，可以大大减少方法调用时间（下次调用直接从该缓存里调用方法）**

利用公式：**key & mask** 来计算出缓存位置**i**（buckets列表里的位置），**如果对应位置已经存在元素，则将i-1（此计算为arm64，x86则是i+1）**，依次类推，直到找到对应位置来存储方法。如果i=0还没找到位置，则将i置为mask（即数组最后一位）。如果数组不够用，则将数组进行扩容；扩容时会将缓存清掉，然后将原来空间扩容2倍，以此类推。

调用方法时也是依据该公式；如果找到的方法对应的key和依据的key不一致，则i-1（x86为i+1），以此类推，直至找到对应方法。

小例子：从buckets缓存中取bucket

```objective-c
bucket_t bucket = buckets[(long long)@selector(personTest) & buckets._mask];
//上述方法取出来的方法有可能是不对的，因为key & mask 公式计算出来的数值有可能不是该方法的位置（上述标黑部分解释了该问题）
```



![cache_t](/Users/wangjl/Downloads/iOS知识点总结/image/cache_t.png)

实例方法调用顺序：先从自己class里的cache缓存列表里去找->再从自己class里的method列表（methods）里去找（二分查找）->父类class里的cache缓存列表里去找->父类class里的method列表（methods）去找（二分查找）...->基类class里的cache缓存列表里去找->基类class里的method列表（methods）里去找（二分查找）。

如果找到方法，不管是在本类中找到的还是在父类中找到的，都把方法缓存到本类的cache_t。

类方法调用顺序，把上面的class换成metaclass。

#### objc_msgSend

**三个阶段：**

##### **1、消息发送阶段（同cache_t章节讲到的方法调用顺序）**![消息发送阶段](/Users/wangjl/Downloads/iOS知识点总结/image/消息发送阶段.png)

##### **2、动态方法解析**  

流程： ![动态方法解析](/Users/wangjl/Downloads/iOS知识点总结/image/动态方法解析.png)

```objective-c
主要方法：
  + (BOOL)resolveInstanceMethod:(SEL)sel;//实例对象动态方法解析
  + (BOOL)resolveClassMethod:(SEL)sel;//类对象动态方法解析

  + (BOOL)resolveInstanceMethod:(SEL)sel{
  //实例对象动态方法解析
  //在本方法中可以添加未找到的方法的实现(假设test方法未实现)
  //实例对象的方法存放在类对象中
  if(sel == @selector(test)){
    Method newMethod = class_getInstanceMethod(self,@selector(newTest));
    /*
    第一个参数：为实例方法所在的类
    第二个参数：未找到的实例方法（需要实现的实例方法）
    第三个参数：新方法的imp
   	第四个参数：新方法的type
    */
		class_addMethod(self,sel,method_getImplementation(newMethod),method_getTypeEncoding(newMethod));
    return YES;
  }
  if(sel == ....){
		...
    return YES;	
  }
    ...
  return [super resolveInstanceMethod:sel];
}

+ (BOOL)resolveClassMethod:(SEL)sel{
  //添加未实现的类方法
  //sel为未实现的方法，假定方法名为test
  if(sel == @selector(test)){
    Method newMethod = class_getClassMethod(object_getClass(self),@selecotr(newTest));//注意：第一个参数为本类的元类对象,self为类对象，object_getClass(self)为self的元类对象
    class_addMethod(object_getClass(self),sel,method_getImplementation(newMethod),method_getTypeEncoding(newMethod));
    return YES;
  }
  if(sel == ....){
		...
    return YES;	
  }
  ...
  return [super resolveClassMethod:sel];
}
```

##### **3、消息转发**

![消息转发](/Users/wangjl/Downloads/iOS知识点总结/image/消息转发.png)

```objective-c
forwardingTargetForSelector://该方法可能是类方法也可能是实例方法，具体看未找到的方法是类方法还是实例方法
1.//先调用forwardingTargetForSelector
- (id)forwardingTargetForSelector:(SEL)aSelector{//此处假设实例方法未实现 类方法用“+”
  if(aSelector == @selector(test)){//此处假设Person实例的test方法未实现
    	return [[Student alloc] init];//如果返回值不为nil，让返回值：Student去帮Person去实现test方法；如果返回为nil，则会调用第2步
  }
  if(...){...}
  ...
    return [Super forwardingTargetForSelector:aSelector];
}

2.//如果forwardingTargetForSelector返回nil 则会调用下面的签名方法
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector{//此处假设实例方法未实现 类方法用“+”
  if(aSelector == @selector(test)){//此处假设Person实例的test方法未实现
    	return [MethodSignature signatureWithObjCTypes:"v16@0:8"];//如果返回不为nil，则调用forwardInvocation:；如果返回为nil，则调用doesNotRecognizeSelector:，控制台打印最经典的错误： unrecognized selector sent to instance xxxxxx ,程序崩溃。
    //return [MethodSignature signatureWithObjCTypes:"v@:"];//上面的方法也可以这么写
  }
  if(...){...}
  ...
    return [Super methodSignatureForSelector:aSelector];
}

3.//如果methodSignatureForSelector方法返回不为nil，则会调用如下方法
  - (void)forwardInvocation:(NSInvocation *)anInvocation{//此处假设实例方法未实现 类方法用“+”
  //do anything 能来到forwardInvocation：方法里，想干什么就干什么，即便写个打印也无所谓
  //[anInvocation getArgument:&xxx atIndex:0];参数1传入一个地址值，并给其赋值；参数2未参数下标。方法默认有顺序：receiver、selector、自定义参数1、自定义参数2...
  //[anInvocation getReturnValue:&xxx];
  //[anInvocation.selector = @selector(test)];
   [anInvocation invokeWithTarget:[[Student alloc] init];
}

```

#### super

![super](/Users/wangjl/Downloads/iOS知识点总结/image/super.png)

```objective-c
[self class]方法最终都是走到了NSObject的class方法，即：
- (Class)getClass{
  return objc_getClass(self);//self传入的是当前对象，例如[[MJStudent alloc] init]对象，得到的是类对象
}
[super class]方法只是比[self class]少了一步往self父类中寻找class方法的步骤，最终也是调用NSObject的class方法，所以最后返回的还是MJStudent
  
补充：
[self superClass];//返回父类
- (Class)superClass{
  return class_getSupserClass(objc_getClass(self));
}
```

#### 面试题

```objective-c
//OC源码：实例对象
- (BOOL)isMemberOfClass(Class)cls{ 
		return [self class] == cls;//直接拿当前的对象去和cls对比
}

- (BOOL)isKindOfClass:(Class)cls{
  	for(Class class = [self class],class,class =  class->superclass){
      if(class == cls) return YES;
    }
  return NO;
}

//OC源码：类对象
+ (BOOL)isMemberOfClass(Class)cls{ 
		return object_getClass((id)self) == cls;//类的类对象是元类，所以此处object_getClass拿到的是元类.
}

+ (BOOL)isKindOfClass:(Class)cls{
  	for(Class class = object_getClass((id)self),class,class =  class->superclass){
      if(class == cls) return YES;
    }
  return NO;
}

 NSLog(@"%d",[NSObject isMemberOfClass:[NSObject class]]);//0
 NSLog(@"%d",[NSObject isKindOfClass:[NSObject class]]);//1
 NSLog(@"%d",[WJLPerson isMemberOfClass:[NSObject class]]);//0，右边是元类对象
 NSLog(@"%d",[WJLPerson isKindOfClass:[NSObject class]]);//1,因为最后的比较条件是（NSObject == NSObject），所以为YES；
 NSLog(@"%d",[WJLPerson isMemberOfClass:[WJLPerson class]]);//0，右边是元类对象
 NSLog(@"%d",[WJLPerson isKindOfClass:[WJLPerson class]]);//0

//总结：isMemberOfClass和isKindOfClass左边如果是实例对象，右边则必须为类对象；如果左边是类对象，那么右侧必须是元类对象（NSObject isKindOfClass:[NSObject class]]这一种情况除外);
//NSObject的元类的isa指针指向的是自己（属于元类），但是NSObject的元类的superclass是NSObject类对象（注意：又变成类对象了，不是元类对象了）。
//类对象/元类对象的isa指向的永远是元类，其中元类的isa统一指向NSObject的元类。
//类对象的superclass指向的永远是类对象；元类的superclass不一定是元类，因为NSObject元类的superclass是NSObject类对象。
//所以：[NSObject isMemberOfClass:[NSObject class]];//返回NO，NSObject的元类 != NSObject类；
//所以：[NSObject isKindOfClass:[NSObject class]];//返回YES，NSObject的元类 != NSObject类,但是NSObject元类的superclass- == NSObject类对象

```

### 6、runtime的应用

#### 1、动态创建类

![动态创建类](/Users/wangjl/Downloads/iOS知识点总结/image/动态创建类.png)

```objective-c
//注意：如果类不需要了，需要调用objc_disposeClassPair(newClass)释放掉
```



#### 2、设置/获取成员变量

![设置:获取成员变量](/Users/wangjl/Downloads/iOS知识点总结/image/设置:获取成员变量.png)

![动态给模型赋值](/Users/wangjl/Downloads/iOS知识点总结/image/动态给模型赋值.png)

#### 3、方法交换

```objective-c
+ (void)load{
    Method orignalMethod = class_getInstanceMethod(self,@selector(viewDidLoad));
    Method newMethod = class_getInstanceMethod(self,@selector(newViewDidLaod));
    
    BOOL isAddMethod = class_addMethod(self, @selector(viewDidLoad), method_getImplementation(newMethod), method_getTypeEncoding(newMethod));
    if (isAddMethod) {
        class_replaceMethod(self,@selector(viewDidLoad),method_getImplementation(newMethod),method_getTypeEncoding(newMethod));
    }else{
        method_exchangeImplementations(orignalMethod,newMethod);
    }
}

- (void)newViewDidLaod{
    NSLog(@"newViewDidLaod");
}

//tips：
//method_exchangeImplementations方法会把方法的imp（方法实现）交换。注意：并不会交换"方法缓存"中的imp，而是将方法缓存全部清空
```

##### ![runtime-method-api](/Users/wangjl/Downloads/iOS知识点总结/image/runtime-method-api.png)

![runtime-method-api2](/Users/wangjl/Downloads/iOS知识点总结/image/runtime-method-api2.png)

例子：动态修改系统设置字体方法，来实现App动态修改字体大小的功能。

## 四、KVO

**概念：**key-value-observing，键值监听，可以用来监听某个对象的属性变化。

**本质：**修改原来的**setter**方法实现。

**原理：**

1. 利用Runtime动态生成一个子类(**NSKVONotifying_XXX**)，并使实例对象的isa指针指向这个子类。（该子类的父类是原来的类**XXX**）

2. 当修改实例对象的属性时，会调用foundation的_NSSetXXXValueAndNotify函数：

   - willChangeValueForKey
   - 调用父类的setter方法
   - 调用didChangeValueForKey：内部会触发监听器（Observer）的监听方法（observerValueForKeyPath:ofObject:change:context:）

   ```objective-c
   //例子：
   - (void)setAge:(int)age{
       //1.willChangeValueForKey
   		[self willChangeValueForKey:@"age"];
   		//2.调用父类的setter方法
       [super setAge:age];
       //3.didChangeValueForKey
   		[self didChangeValueForKey:@"age"];
   }
   ```

   

**手动启动kvo：**

手动调用[person **willChangeValueForKey**:@"age"]以及[person **didChangeValueForKey**:@"age"]；

## 五、KVC

**概念：**Key-Value-Coding，键值编码，给属性赋值。

**setValue:forKey:原理图：**

![kvc原理图](/Users/wangjl/Downloads/iOS知识点总结/image/kvc原理图.png)

**Tips：KVC可以触发KVO。**

**valueForKey:原理图**

![kvc原理图2](/Users/wangjl/Downloads/iOS知识点总结/image/kvc原理图2.png)



## 六、category

### 1、**本质：**

- 每个分类都会在编译期生成如下的结构体（一个_category_t代表一个分类）。
- ![image](https://github.com/DaZhuzhu/iOS-Interview/blob/master/image/_category_t.png)

- 通过runtime（运行时），动态将分类里的信息（方法列表、属性列表、协议列表等）合并到类对象、元类对象中。

**如果类对象和分类对象有相同的方法实现，则会调用分类的方法实现，不会调用类对象里的方法实现。（类似重写，但其实是假的重写，因为类对象的方法实现并没有被抹去）**

**最后编译的分类，其方法列表会放在对应的类的methods的最前面，其他分类（类对象）的方法列表后移（类对象的方法列表会移到最后），这也是为什么同样的方法实现，会优先调用分类的方法实现，因为它在类的methods最前面。![合并category方法列表](/Users/wangjl/Downloads/iOS知识点总结/image/合并category方法列表.png)**

```objective-c
//类扩展（Extension和分类（Category）的区别：
/*
Extension：编译期就将对应的信息（属性、方法、协议等）合并到类（元类）对象中，相当于把公有的属性、方法私有化。
Category： 运行时将分类的信息（属性列表、方法列表、协议等）合并到类（元类）对象中。
*/
```

### 2、load

load方法在runtime加载类、分类时被调用，且只调用一次，不管该类是否被调用/引用。

调用顺序：**先调用项目中所有类的load方法（按编译顺序），才会调用所有分类的load方法（按编译顺序）；**而且class的load调用顺序为：**父类laod-->子类load-->再按照category的编译顺序调用category的load方法**。

```c++
//解答：load方法底层调用是从一个loadable_classes数组中取类对象，然后取出类对象的load方法直接进行调用（(*load_method)(cls.SEL_load)）,而loadable_classes中类对象的存储顺序就是load的调用顺序；runtime加载类、分类时，会将类和分类添加到loadable_classes数组中，而且添加顺序是先添加其父类然后再添加本类，然后再按照编译顺序添加分类到loadable_classes中。所以，load的调用顺序如上所述。
```

**问题：为什么类对象的load方法没有被分类取代？（即分类实现了load方法，但是程序加载时类对象的load方法还可以被调用）**

```c++
//解答：load方法不是遍历去取方法，而是直接从类对象中取出该方法地址，然后去调用。
load_method_t load_method = (load_method_t)classes[i].method;

//而其他的方法，则是通过下面方式去调用方法
objc_msgSend([XXX class],@selector(test));
//先找到对应的类（元类），然后从类（元类）方法列表里去取该方法，顺序为：分类->类；如果没找到该方法，则从类（元类）父类中寻找该方法...

```

问题2：

## 四、UI

### **1、CAlayer和UIView的区别和联系**

**联系：**UIView 和 CALayer 是相互依赖的关系。UIView 依赖于 calayer 提供的内
容，CALayer 依赖 uivew 提供的容器来显示绘制的内容。归根到底 CALayer 是
这一切的基础，如果没有 CALayer，UIView 自身也不会存在，UIView 是一个
特殊的 CALayer 实现，添加了响应事件的能力。

**区别：**1、CALayer不可以响应事件，UIView可以响应事件。2、CALayer的父类是NSObject，UIView的父类是UIResponder。

**（插播一条新闻：iPhone12状态栏高度是47，导航栏高度是44+47=91；iPhonex是44，导航栏是44+44=88）**

## 五、block

## 六、性能优化

## 七、设计模式

## 八、网络

## 九、数据结构



