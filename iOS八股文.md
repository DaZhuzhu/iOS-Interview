#     iOS知识点总结

## 一、runloop

### 1、概念及作用

**概念**：RunLoop（运行循环）是 iOS/macOS 开发中的**事件处理机制**，用于管理和调度线程的任务（如触摸事件、定时器、网络回调等），确保线程在有任务时执行，无任务时休眠，避免资源浪费。底层是基于 **CFRunLoop** 实现的，CFRunLoop 内部有个 do while 方法来实现 runloop。

```objective-c
while (1) {
    // 1. 检查事件（如果有则处理）
    // 2. 无事件时调用 mach_msg()，线程挂起
}
```

`mach_msg()` 是 **阻塞式系统调用**，调用后线程会被移出 CPU 调度队列，**直到内核唤醒它**。此时 `while` 循环的代码 **完全停止执行**，自然不消耗 CPU。

**作用：**

- 保持程序的持续运行

- 处理`APP`中的各种事件（触摸、定时器、`performSelector`）

- 节省`cpu`资源、提高程序的性能：该做事就做事，该休息就休息

  面试题：你了解runloop吗？项目中哪些地方用到了？
  
  回答：runloop 是事件循环机制，他能监听并处理各种事件，例如触摸事件、定时器等，并能保证程序持续运行而不退出。用到的地方，定时器，检测 fps 值。

### 2、和线程的关系

和线程一一对应，其关系保存在一个全局的字典里，key 为线程（pthread_t），value 为 runloop（CFRunLoopRef）。

主线程的 runloop 系统自动创建。子线程中的runloop在第一次获取的时候创建，**当线程退出时，runloop销毁**。

**子线程中默认没有 runLoop，除非主动去获取**

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
	 CFRunLoopStop(CFRunLoopGetCurrent());// 注意：要在合适的时机停掉runloop，否则可能会导致内存泄漏
}
```



### 3、runloop 的接口

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

- Source0 只包含了一个回调（函数指针），它并不能主动触发事件。使用时，你需要先调用 CFRunLoopSourceSignal(source)，将这个 Source 标记为待处理，然后手动调用 CFRunLoopWakeUp(runloop) 来唤醒 RunLoop，让其处理这个事件。例如：

  - **触摸事件（Touch Events）：** 当用户在应用程序中进行触摸操作时，触摸事件将被作为 Source0 事件添加到主线程的 Run Loop 中。通过观察者注册回调方法，可以在 Run Loop 中处理触摸事件，例如更新用户界面或执行相应的操作。

  - **定时器事件（Timer Events）：** 使用 NSTimer 或 GCD 的定时器时，定时器事件会被添加为 Source0 事件到 Run Loop 中。当定时器触发时，Run Loop 的观察者将通知相应的回调方法，以执行预定的操作。

  - **自定义事件（Custom Events）：** 在某些情况下，应用程序可能需要发送自定义事件，例如自定义通知或消息。这些自定义事件可以作为 Source0 事件添加到 Run Loop 中，并通过观察者来处理。

  **特点：**

  - 需要手动触发 ，CFRunLoopSourceSignal发送信号，CFRunLoopWakeUp唤醒runloop
  - 优先级较高

- Source1：基于端口的事件源，用于处理系统内核事件和其他一些异步事件，比如
  * 电池状态改变、网络连接状态改变
  * 异步网络请求：网络请求结束后，会以srouce1事件的形势发送到主线程的runloop中
  * 基于port的线程间通信：[NSThread detachNewThreadSelector:@selector(launchThreadWithPort:) toTarget:self.work withObject:self.myPort];，注意要遵循nsport的协议，然后实现handleportMessage方法

  **特点：**

  * 自动处理
  * 优先级较低

####  3、CFRunLoopTimerRef

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
    dispatch_semaphore_signal(semaphore);
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

            if (st != 0) {  
                // dispatch_semaphore_wait方法返回值（st）是个错误码，0：未超时，非0：超时
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

附加知识点：`dispatch_semaphore_wait`函数的返回值是一个`long`类型的整数。

如果信号量（semaphore）的值大于0，`dispatch_semaphore_wait`会使信号量的值减1并立即返回，此时返回值为0，表示成功获取了资源。

如果信号量的值为0，那么`dispatch_semaphore_wait`会阻塞当前线程直到信号量的值大于0或者超时。如果在超时时间内，信号量的值变为了大于0，函数就会使信号量的值减1并返回0；如果超时时间结束时，信号量的值仍然为0，函数就会返回非0的值，具体来说，这是一个错误码，表示超时或者出错。

简而言之，`dispatch_semaphore_wait`的返回值为0表示成功获取了资源，非0表示在指定的超时时间内未能获取资源。

#### 2、NSTimer

#### 3、performselector

#### 4、自动释放池

## 二、多线程

**程序中有多条线程在执行任务。**

### 1、进程和线程

**进程：**

1. **进程是计算机中正在执行的程序的实例。它是一个独立的执行单位，包含了程序代码、数据和系统资源;**
2. 在iOS 中 一个进程就是一个正在运行的一个应用程序; 比如 QQ.app ，而且一个app只能有一个进程，不像安卓支持多个进程
3. 每一个进度都是独立的，每一个进程均在专门且受保护的内存空间内;
4. iOS中是一个非常封闭的系统，每一个App（一个进程）都有自己独特的内存和磁盘空间，别的App（进程）是不允许访问的（越狱不在讨论范围）；

**线程：**

1. **线程是进程内的一个执行单元，一个进程中可以包含多个线程，所有线程共享进程的地址空间和资源。一个进程（App）至少有一个线程，这个线程叫做主线程；**
2. 线程是CPU调度的最小单元；
3. 线程的作用：执行app的代码；

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

死锁

```objective-c
例1：
  //在同一串行队列的一个任务中，添加同步任务。
  dispatch_queue_t serQueue = dispatch_queue_create("com.Damon.GCDSerial", DISPATCH_QUEUE_SERIAL);

  dispatch_async(serQueue, ^{

      NSLog(@"2");

      dispatch_sync(serQueue, ^ {//在当前的串行队列里添加此处造成死锁
          NSLog(@"3");
      });

      NSLog(@"4");
 });

例2：
//使用sync往主队列中添加任务，会造成死锁（卡住当前的串行队列）;也叫同步主队列造成死锁。
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

 **group**

```objective-c
方式一：
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

方式二：
  dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSLog(@"第一条");
        dispatch_group_leave(group);
    });
    
    dispatch_group_enter(group);
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSLog(@"第2条");
        sleep(2);
        dispatch_group_leave(group);
    });
    
    dispatch_group_enter(group);
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSLog(@"第3条");
        sleep(3);
        dispatch_group_leave(group);
    });
    
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        NSLog(@"都执行完了");
    });
```

#### 4、NSOperation

基于GCD（底层是GCD）

例子：某一线程在指定线程之后执行操作

```objective-c
		NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    
    NSBlockOperation *a = [NSBlockOperation blockOperationWithBlock:^{
        NSLog(@"a--thread:%@",[NSThread currentThread]);
    }];
    
    NSBlockOperation *b = [NSBlockOperation blockOperationWithBlock:^{
        NSLog(@"b--thread:%@",[NSThread currentThread]);
    }];
    
    NSBlockOperation *c = [NSBlockOperation blockOperationWithBlock:^{
        NSLog(@"c--thread:%@",[NSThread currentThread]);
        sleep(3);
    }];
    
    NSBlockOperation *d = [NSBlockOperation blockOperationWithBlock:^{
        NSLog(@"d--thread:%@",[NSThread currentThread]);
    }];
    
    NSBlockOperation *e = [NSBlockOperation blockOperationWithBlock:^{
        NSLog(@"e--thread:%@",[NSThread currentThread]);
    }];
    
    [d addDependency:a]; // d在a执行完之后才执行
    [d addDependency:b]; // d在b执行完之后才执行
    
    [e addDependency:b]; // e在b执行完之后才执行
    [e addDependency:c]; // e在c执行完之后才执行
    
    [queue addOperations:@[a,b,c,d,e] waitUntilFinished:NO];
```



#### 注意：解决线程的安全问题方案：

1、使用线程同步

2、加锁

### 3、异步/同步、并发/串行

**异步/同步：**

异步：开启新线程。在新线程中执行任务。

同步：不开线程。只在**当前线程**中执行任务，立马去执行当前线程中的任务。

**线程同步方案性能比较：**

**os_unfair_lock > OSSpinLock > dispatch_semaphore > pthread_mutex > dispatch_queue(DISPATCH_QUEUE_SERIAL) > NSLock > NSCondition > pthread_mutex(recursive) > NSRecursiveLock > NSConditionLock > @synchronized** 

**队列：存放任务的结构**

并发队列：可多个任务并发执行，需要开启新线程执行多个任务。**只在异步函数下有效。**

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

//同步并发：不开线程 串行执行 主线程
dispatch_queue_t syncSeriCon = dispatch_queue_create("com.test.wjlSyncCon", DISPATCH_QUEUE_CONCURRENT);
for (int i = 0; i< 100 ;i++) {
  dispatch_sync(syncSeriCon,^{
      NSLog(@"同步并行--i:%d 当前线程：%@",i,[NSThread currentThread]);//主线程
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

#### 3、使用条件锁NSConditionLock

#### 4、通过全局变量、共享内存的方式实现。但这种会造成资源抢夺，线程安全问题。

#### 5、基于port的线程间的通信

```objective-c
//ThreadVC
#define kMsg1 100
#define kMsg2 101
@interface ThreadVC ()<NSMachPortDelegate>
@property (nonatomic, copy)NSPort *myPort;
@property (nonatomic, strong)MyWorkerClass *work;

@end

@implementation ThreadVC
- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSLog(@"viewDidLoad thread is %@.", [NSThread currentThread]);
    
    self.myPort = [NSMachPort port];
    self.myPort.delegate = self;
    [[NSRunLoop currentRunLoop] addPort:self.myPort forMode:NSDefaultRunLoopMode];
    
    self.work = [[MyWorkerClass alloc] init];
    [NSThread detachNewThreadSelector:@selector(launchThreadWithPort:) toTarget:self.work withObject:self.myPort];
}

- (void)handlePortMessage:(NSMessagePort *)message
{
    NSLog(@"接受到子线程传递的消息。%@", message);
    NSLog(@"handlePortMessage thread is %@.", [NSThread currentThread]); // main thread
  
    NSUInteger msgId = [[message valueForKeyPath:@"msgid"] integerValue];
    NSMachPort *localPort = [message valueForKeyPath:@"localPort"];
    NSMachPort *remotePort = [message valueForKeyPath:@"remotePort"];
    NSMutableArray *componts = [message valueForKey:@"components"];
    
    for (NSData *data in componts) {
        NSLog(@"data is %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    }
    
    if (msgId == kMsg1) {
        [remotePort sendBeforeDate:[NSDate date] msgid:kMsg2 components:nil from:localPort reserved:0];
    }
}


//MyWorkerClass 来执行子线程中的操作 执行完之后通知给主线程(ThreadVC在handlePortMessage代理回调里接受该通知)
#import "MyWorkerClass.h"
#define kMsg1 100
#define kMsg2 101

@interface MyWorkerClass () <NSMachPortDelegate>

@property (nonatomic, strong) NSPort *remotePort;
@property (nonatomic, strong) NSPort *myPort;

@end

@implementation MyWorkerClass

- (void)launchThreadWithPort:(NSPort *)port
{
      self.remotePort = port;

      [[NSThread currentThread] setName:@"MyWorkerClass"];

      NSLog(@"launchThreadWithPort thread is %@.", [NSThread currentThread]); // 子线程

      self.myPort = [NSMachPort port];
      self.myPort.delegate = self;

      [[NSRunLoop currentRunLoop] addPort:self.myPort forMode:NSDefaultRunLoopMode];

      [self sendPortMessage];

      [[NSRunLoop currentRunLoop] run];//必须写在sendPortMessage下面，否则方法不执行

}

- (void)sendPortMessage
{
    NSData *data1 = [@"wang" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *data2 = [@"yinan" dataUsingEncoding:NSUTF8StringEncoding];
    
    NSMutableArray *array = [[NSMutableArray alloc] initWithArray:@[data1, data2]];
    [self.remotePort sendBeforeDate:[NSDate date] msgid:kMsg1 components:array from:self.myPort reserved:0];
}


- (void)handlePortMessage:(NSMessagePort *)message
{
    NSLog(@"接受到父类的消息。。。%@。", message);
}
```



### 5、线程锁

锁的性能对比（单线程）：最上面性能最高

![lock_benchmark](/Users/wangjl/Downloads/iOS知识点总结/image/线程锁性能对比.png)

**os_unfair_lock > OSSpinLock > dispatch_semaphore > pthread_mutex > dispatch_queue(DISPATCH_QUEUE_SERIAL) > NSLock > NSCondition > pthread_mutex(recursive) > NSRecursiveLock > NSConditionLock > @synchronized** 

#### 1、互斥锁

**概念**：当一个线程尝试获取一个互斥锁时，如果锁已经被其他线程持有，则该线程将被阻塞，直到互斥锁被解锁。当互斥锁被解锁时，**操作系统**会**通知**被阻塞的线程，使其继续执行。这种处理方式就叫做互斥锁。（当上一个线程里的任务没有执行完毕的时候，那么下一个线程的任务会进入睡眠状态；当上一个任务执行完毕时，下一个线程会自动唤醒然后执行任务。）

##### 1、@synchronized 关键字加锁

使用方法：

```objective-c
@synchronized(这里添加一个OC对象，一般使用self) {
	// 这里写要加锁的代码
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
pthread_mutex_destroy(&mutex)
  
打印：
2021-10-22 15:59:42.683841+0800 DefaultDemo[8383:1611181] 任务1
2021-10-22 15:59:45.687680+0800 DefaultDemo[8383:1611175] 任务2

```



#### 2、spin lock 自旋锁（自旋锁已不被推荐使用）

**概念：**线程反复检查锁变量是否可用，一直占用cpu；由于线程在这一过程中保持执行，因此是一种忙等状态。一旦获取了自旋锁，线程会一直持有该锁，直至显式释放自旋锁。

获取、释放自旋锁，实际上是读写自旋锁存储内存或寄存器。因此这种读写操作必须是原子的（atomic）。再次强调：被atomic修饰的属性，内部其实也是受**互斥锁**保护的！

**优点：充分利用cpu资源**

**缺点：耗性能**

##### 1、OSSpinLock （不推荐使用）

需要导入头文件**<libkern/OSAtomic.h>**

不安全，被弃用。原因：具体来说，如果一个**低优先级**的线程获得锁并访问共享资源，这时一个**高优先级**的线程也尝试获得这个锁，**高优先级**会处于 spin lock 的忙等状态从而占用大量 CPU。此时**低优先级**线程无法与**高优先级**线程争夺 CPU 时间，从而导致任务迟迟完不成、无法释放 lock，导致陷入**死锁**。（即**优先级反转**的问题）

**os_unfair_lock**用于取代OSSpinLock，从iOS10开始支持。从底层看，等待os_unfair_lock锁的线程会处于休眠状态，并非忙等（**所以os_unfair_lock是互斥锁**）。（需要导入头文件：**<os/lock.h>**）

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

**注意：**被**atomic**修饰的属性，**内部**其实也是受**互斥锁**保护的（系统源码中或许使用的是spinlock的名字，但其实早已改为互斥锁，只是名字没有改而已），但其并不是线程安全的！只不过内部对属性的getter和setter加锁，但是外部对属性的修改并没有加锁。

```objective-c
// 线程1
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (int i = 0; i < 1000; i++) {
            self.number = self.number + 1;
            NSLog(@"number: %ld", self.number);
        }
    });
    
    // 线程2
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (int i = 0; i < 1000; i++) {
            self.number = self.number + 1;
            NSLog(@"number: %ld", self.number);
        }
    });
```

属性是`atomic`修饰的，按理说应该是线程安全的，两个线程各对`number`做了1000次循环`+1`，最终`numer`的值应该是`2000`，但输出的值却不是期望的`2000`。

```yaml
// 最后的几行输出
2020-03-07 22:37:21.713683+0800 TestObjC[23813:2171198] number: 1986
2020-03-07 22:37:21.714004+0800 TestObjC[23813:2171198] number: 1987
2020-03-07 22:37:21.714267+0800 TestObjC[23813:2171198] number: 1988
2020-03-07 22:37:21.714541+0800 TestObjC[23813:2171198] number: 1989
2020-03-07 22:37:21.714844+0800 TestObjC[23813:2171198] number: 1990
2020-03-07 22:37:21.715027+0800 TestObjC[23813:2171198] number: 1991
2020-03-07 22:37:21.715442+0800 TestObjC[23813:2171198] number: 1992
```

以上是输出的最后几行，最终的值只加到`1992`。这是因为两个线程在并发的调用`setter`和`getter`，在`setter`和`getter`内部是加了锁，但是在做`+1`操作的时候并没有加锁，导致在某一时刻，线程一调用了`getter`取到值，线程2恰好紧跟着调用了`getter`，取到相同的值，然后两个线程对取到的值分别`+1`，再分别调用`setter`，使得两次`setter`其实赋值了相等的值。

- 因此使用`atomic`修饰属性时对属性的操作是否是线程安全的，虽然在内部加了锁，但并不能保证绝对的线程安全。

上面的代码可以在self.number = self.number + 1;处加锁，用来保证线程安全



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
      // [lock lock];// 重复调用会造成死锁，所以只打印了value：5
      [recursiveLock lock];// 重复调用不会造成死锁，

      NSLog(@"value:%d",value); // 会打印value：5 - value：0
      if (value > 0) {
          value -- ;
          testRecursiveLock(value);
      }
      // [lock unlock];
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

**dispatch_semaphore_signal(semaphore)**：会让value+1，value>0时，当前线程会被唤醒，执行队列中剩余的任务。

**dispatch_semaphore_wait(semaphore,timeout)**：如果value=0，代表无多余资源可用，当前线程会进入睡眠状态（被锁住），被锁住多久，取决于timeout参数，DISPATCH_TIME_FOREVER表示无限期休眠，如果指定锁住多少秒，则指定时间结束后，会继续向下执行，但**value值不减一**。如果value > 0,那么会继续执行，并让**value - 1**

```objective-c
dispatch_semaphore_t semaphore;
@implementation Lock_All_Test
- (void)test{
    semaphore = dispatch_semaphore_create(0);

    dispatch_async(dispatch_get_global_queue(0, 0),^{
      NSLog(@"1");
      sleep(3);
      dispatch_semaphore_signal(semaphore);
    });

    dispatch_async(dispatch_get_global_queue(0, 0),^{
       dispatch_semaphore_wait(semaphore,DISPATCH_TIME_FOREVER);
       NSLog(@"2");
    });
}

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
  NSLog(@"conditon1");
  [conditionLock unlockWithCondition:2];
});

dispatch_async(queue2,^{
  [conditionLock lockWhenCondition:2];//当条件值为2的时候开始加锁，并执行下面代码
  NSLog(@"conditon2");
  [conditionLock unlockWithCondition:3];
});

dispatch_async(queue1,^{
  [conditionLock lockWhenCondition:3];
   NSLog(@"conditon3");
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

传入的队列必须是自己**手动通过dispatch_queue_create创建**的**并发队列**；

如果传入的是**串行队列**或**全局并发队列**，那么它的效果同**dispatch_sync或dispatch_async**（具体看线程是同步还是异步）

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
注意：上面的打印1和2的顺序是不确定的，但是3必须在barrier之后打印
```

Dispatch_barrier_async也可以实现**多读单写**操作

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

### 6、线程保活

### 基于 RunLoop 的保活（最常用）

RunLoop 是线程的 “事件循环机制”，若能让线程的 RunLoop 持续运行，即可实现保活。核心步骤：

1. **为线程创建并配置 RunLoop**
   线程默认无 RunLoop，需主动获取（`[NSRunLoop currentRunLoop]`），并添加 “输入源”（Source）或 “定时源”（Timer）——RunLoop 若无可处理的事件源，会直接退出。

   - 通常添加一个 “空的 Port” 作为 Source（无需实际通信，仅维持 RunLoop 运行）：

     ```objective-c
     NSThread *thread = [[NSThread alloc] initWithTarget:self selector:@selector(threadMain) object:nil];
     [thread start];
     
     // 线程主函数
     - (void)threadMain {
         @autoreleasepool {
             // 创建Port并添加到RunLoop
             NSPort *port = [NSPort port];
             [[NSRunLoop currentRunLoop] addPort:port forMode:NSDefaultRunLoopMode];
             // 启动RunLoop（会持续循环，直到被手动停止）
             [[NSRunLoop currentRunLoop] run];
         }
     }
     ```

### 7、应用实例

#### 1. 如何让任务按照指定顺序执行？

方法1：使用串行队列

方法2：使用NSOperation的addAppendency

方法3：使用NSConditionLock加锁

## 三、Runtime （运行时）

概念：OC 是一门动态性比较强的编程语言，允许许多操作推迟到运行时在进行，OC 的动态性就是由Runtime去支撑的，Runtime 是一套C 语言的 API，封装了很多动态性相关的函数，平时编写的 OC 代码，底层都转成了 Runtime API 进行调用

**使用场景：**

1. JSON 模型转换（如 MJExtension/YYModel 底层）
2. 给分类（Category）添加属性
3. 方法交换（Method Swizzling）
4. KVO 底层实现

### 1、动态性

1. **动态类型识别**（Dynamic Typing）：Objective-C 是一种动态类型语言，可以在运行时检查对象的类型，以及在一定程度上进行类型转换和查询。这使得开发者能够在运行时处理不同类型的对象，并根据实际情况进行动态操作。
2. **动态方法解析**（Dynamic Method Resolution）：Objective-C 运行时允许在运行时动态地为对象添加方法或替换已存在的方法实现。这使得开发者可以根据需要动态地扩展对象的功能，实现动态行为和运行时的逻辑。
3. **消息转发**（Message Forwarding）：当对象接收到无法处理的消息时，Objective-C 运行时提供了消息转发机制，允许开发者在运行时动态地决定如何处理该消息。这为对象之间的通信和交互提供了更大的灵活性和可扩展性。
4. **动态类创建和修改**：Objective-C 运行时允许在运行时动态地创建类、修改类的实例变量、方法和属性等。这为动态类的创建、扩展和修改提供了可能，例如在运行时创建类簇或实现运行时注入等功能。

**多态**：不同对象以自己的方式响应相同的消息的能力叫做多态。

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


typedef struct objc_class *Class; // 类对象
typedef struct objc_object *id; // 实例对象

// 实例对象内存布局
struct objc_object {
private:
    isa_t isa;
}
// isa 指针内存布局
union isa_t {
    isa_t() { }
    isa_t(uintptr_t value) : bits(value) { }

    Class cls; // 指向自己的类
    uintptr_t bits; // 存储实例对象所有的变量数据
#if defined(ISA_BITFIELD)
    struct {
        ISA_BITFIELD;  // defined in isa.h
    };
#endif
};

// 类对象的内存布局（此处注释里，只解释了类对象，不包括对元类对象的解释）
struct objc_class : objc_object {
    // Class ISA; // 指向元类
    Class superclass; // 指向父类
    cache_t cache;             // 类里缓存的方法列表（被实例对象调用过的方法列表）
    class_data_bits_t bits;    // 存储类对象所有的数据

    class_rw_t *data() { // bits & FAST_DATA_MASK 会拿到data
        return bits.data(); // 里面包含了类的属性列表、协议列表、方法列表、flags、version...
    }
}
/*
*oc源码里面共用体一般如下结构
*从arm64架构开始，对isa进行了优化，变成了一个共用体(union ）结构，还使用位域来存储更多的信息，节省内存空间
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

#### **isa**

**概念：**一个指针，存储Class和Meta-class的内存地址以及其他信息（比如对象引用计数、析构状态等）

- 实例对象的isa指向类对象
- 类对象的isa指针指向元类对象
- 元类对象的isa指针指向元类的基类

```json
实例对象 (Instance)
│
├── isa 指针
↓
类对象 (Class)  // 存储实例方法、属性、协议等信息
│
├── isa 指针
↓
元类 (Meta Class)  // 存储类方法等信息
│
├── isa 指针
↓
根元类 (Root Meta Class)  // NSObject的元类
│
├── isa 指针 (指向自身形成闭环)
└───┐
    ↑______│
│
├── superclass 指针
↓
根类 (Root Class)  // NSObject类
│
├── superclass 指针
↓
nil  // 终点
```

从arm64架构开始，对 isa 进行了优化，变成了一个共用体(union）结构，来存储更多的信息

**isa 在内存中的演进**

1. **传统指针（Tagged Pointer 前时代）**

- 早期 `isa` 是纯指针（`Class isa`），直接存储类/元类的内存地址。
- **问题**：64位系统下指针占用8字节，内存浪费严重。

2. **非指针 isa（Non-pointer isa）**

- **目标**：优化内存与性能（苹果在ARM64架构引入）。

- **原理**：利用64位地址的**高位未使用空间**，存储额外信息（对象引用计数、析构状态，或小整数、短字符串等数据）。

- **数据结构**（简化伪代码）：

  ```c++
  struct {
      uintptr_t nonpointer        : 1;  // 标记是否为非指针isa
      uintptr_t has_assoc         : 1;  // 是否有关联对象
      uintptr_t has_cxx_dtor      : 1;  // 是否有C++析构函数
      uintptr_t shiftcls          : 33; // 类/元类的实际地址（偏移后）
      uintptr_t magic             : 6;  // 对象初始化完成标记
      uintptr_t weakly_referenced : 1;  // 是否有弱引用
      uintptr_t deallocating      : 1;  // 是否正在释放
      uintptr_t has_sidetable_rc  : 1;  // 引用计数是否过大（需SideTable存储）
      uintptr_t extra_rc          : 19; // 额外的引用计数（直接存储）
  };
  ```

- **关键操作**：

  - **获取类地址**：`cls = (Class)(isa & ISA_MASK)`（通过位掩码 `ISA_MASK` 提取 `shiftcls`）。
  - **优势**：单字节能存更多信息，减少内存访问次数。

**Tagged Pointer** 是 iOS 系统（从 64 位架构开始引入）对小数据对象的一种**内存优化技术**，核心是 “把数据直接存在指针变量里”，而非让指针指向堆内存中的对象 —— 相当于让指针本身变成 “数据容器”，不用额外分配堆内存。

**为什么需要它？**

像 `NSNumber`（包装小整数、`BOOL`）、`NSString`（短字符串）、`NSDate`（简单日期）这类 “小数据对象”，如果按普通对象处理：

- 需在堆上分配内存（至少 16 字节，含 `isa` 指针等基础结构）；
- 还要通过指针间接访问数据，有额外开销。

但它们的数据本身很小（比如一个 `int` 仅 4 字节，短字符串几个字符），完全能塞进 64 位的指针变量里。`Tagged Pointer` 就利用这一点，直接把数据存指针里，省去堆内存分配和访问的成本。

**cache **里利用散列表(哈希表）形式保存了调用过的方法，如此设计可以大大优化函数调用时间。

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
  上面的方法type值即：i24@0:8i16f20 //其中i代表返回值为int类型；24代表方法参数共占24个字节;@代表参数类型为id，0代表内存从第0个字节开始计算；“：”代表参数为SEL，8代表 内存从第8个字节开始计算；....
  iOS提供了一个叫作@encode的指令，可以将具体的类型表示为字符串编码
  ```

  ![type encoding](/Users/wangjl/Downloads/iOS知识点总结/image/type encoding.png)
  
  **小tip：每一个方法都默认包含两个参数：self和_cmd**
  
  ```objective-c
  - (void)test;
  //上述方法包含了两个参数：self 和 _cmd(_cmd=@selector(test))所以同下
  - (void)test:(id)self _cmd(SEL)cmd;//self表示方法所在的类实例对象，cmd表示当前的selector
  ```
  
  

#### cache_t 

**方法缓存，用来缓存已经调用过的方法，可以大大减少方法调用时间（下次调用直接从该缓存里调用方法）**

利用公式：**key & mask** 来计算出缓存位置**i**（buckets列表里的位置），**如果对应位置已经存在元素，则将i-1（此计算为arm64，x86则是i+1）**，依次类推，直到找到对应位置来存储方法。如果i=0还没找到位置，则将i置为mask（即数组最后一位）。如果数组不够用，则将数组进行扩容；扩容时会将缓存清掉，然后将原来空间扩容2倍，以此类推。

调用方法时也是依据该公式；如果找到的方法对应的key和依据的key不一致，则i-1（x86为i+1），以此类推，直至找到对应方法。

小例子：从buckets缓存中取bucket

```objective-c
bucket_t bucket = buckets[(long long)@selector(personTest) & buckets._mask];
//上述方法取出来的方法有可能是不对的，因为key & mask 公式计算出来的数值有可能不是该方法的位置（上述标黑部分解释了该问题）
```

实例方法调用顺序：先从自己class里的cache缓存列表里去找->再从自己class里的method列表（methods）里去找（二分查找）->父类class里的cache缓存列表里去找->父类class里的method列表（methods）去找（二分查找）...->基类class里的cache缓存列表里去找->基类class里的method列表（methods）里去找（二分查找）。

如果找到方法，不管是在本类中找到的还是在父类中找到的，都把方法缓存到本类的cache_t。

类方法调用顺序，把上面的class换成metaclass。

#### objc_msgSend

**三个阶段：**

##### **1、消息发送阶段**

同cache_t章节讲到的方法调用顺序

##### **2、动态方法解析**  

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
      // 如果返回不为nil，则调用forwardInvocation:；
      // 如果返回为nil，则调用doesNotRecognizeSelector:，控制台打印最经典的错误： unrecognized selector sent to instance xxxxxx ,程序崩溃。
    	return [MethodSignature signatureWithObjCTypes:"v16@0:8"];
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

总结objc_msgSend流程：

1. 先走消息发送（顺序见**cache_t**部分讲解）,若未找到方法实现，走第2步。注意：如果方法接受者是nil，不会崩溃。
2.  动态方法解析，调用**resolveInstanceMethod**/**resolveClassMethod**方法，并且在方法里给未找到的方法新增了方法实现，则会调用新的方法实现，若未新增方法实现则进行第3步。
3. 消息转发，调用**forwardingTargetForSelector**，如果返回不为nil，则让返回对象去执行对应的方法；返回为nil，则调用方法签名**methodSignatureForSelector**，如果方法签名返回不为nil，则会调用**forwardInvocation**（方法里可以做任何事情），如果方法签名返回nil，则崩溃，控制台打印**unrecognized selector sent to instance xxxxxx**。

#### super

```objective-c
[self class]方法最终都是走到了NSObject的class方法，即：
- (Class)getClass{
  return objc_getClass(self);//self传入的是当前对象，例如[[MJStudent alloc] init]对象，得到的是MJStudent类对象
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
      //循环遍历拿自己的父类同传入的cls进行对比
      if(class == cls) return YES;
    }
  return NO;
}

 NSLog(@"%d",[NSObject isMemberOfClass:[NSObject class]]);//0 右边应该是元类对象
 NSLog(@"%d",[NSObject isKindOfClass:[NSObject class]]);//1 
 NSLog(@"%d",[WJLPerson isMemberOfClass:[NSObject class]]);//0，右边应该是元类对象
 NSLog(@"%d",[WJLPerson isKindOfClass:[NSObject class]]);//1,因为最后的比较条件是（NSObject == NSObject），所以为YES；
 NSLog(@"%d",[WJLPerson isMemberOfClass:[WJLPerson class]]);//0，右边应该是元类对象
 NSLog(@"%d",[WJLPerson isKindOfClass:[WJLPerson class]]);//0 
 NSLog(@"%d",[ClassObj isKindOfClass:object_getClass(ClassObj.class)]);//1

//总结：isMemberOfClass 和 isKindOfClass 左边如果是实例对象，右边则必须为类对象；如果左边是类对象，那么右侧必须是元类对象（NSObject isKindOfClass:[NSObject class]]这一种情况除外);
//NSObject 的元类的 isa 指针指向的是自己（属于元类），但是 NSObject 的元类的 superclass 是 NSObject 类对象（注意：又变成类对象了，不是元类对象了）。
//类对象/元类对象的 isa 指向的永远是元类，其中元类的 isa 统一指向 NSObject 的元类。
//类对象的 superclass 指向的永远是类对象；元类的 superclass 不一定是元类，因为 NSObject 元类的 superclass 是 NSObject 类对象。
//所以：[NSObject isMemberOfClass:[NSObject class]];//返回NO，NSObject的元类 != NSObject类；
//所以：[NSObject isKindOfClass:[NSObject class]];//返回YES，NSObject的元类 != NSObject类,但是NSObject元类的superclass == NSObject类对象

```

### 6、runtime的应用

#### 1、动态创建类

在 iOS 中，可以使用 Objective-C 运行时提供的函数和 API 来动态地创建类。下面是一种常见的方法：

1. 使用 `objc_allocateClassPair` 函数创建一个新的类，并指定类名和父类。例如，要创建一个名为 `MyClass` 的类，父类为 `NSObject`，可以使用以下代码：

   ```
   Class newClass = objc_allocateClassPair([NSObject class], "MyClass", 0);
   ```

2. 使用 `class_addMethod` 函数向新创建的类中添加方法。这个函数接受类对象、方法选择器、方法实现和方法的类型编码作为参数。例如，要向 `MyClass` 类中添加一个名为 `myMethod` 的方法，可以使用以下代码：

   ```
   void myMethodIMP(id self, SEL _cmd) {
       // 实现方法的代码
   }
   
   class_addMethod(newClass, @selector(myMethod), (IMP)myMethodIMP, "v@:");
   ```

   这里的方法类型编码 `"v@:"` 表示返回值为 `void`，没有参数。

3. 最后，使用 `objc_registerClassPair` 函数将新创建的类注册到运行时系统中，使其可用。例如：

   ```
   objc_registerClassPair(newClass);
   ```

```objective-c
//注意：如果类不需要了，需要调用objc_disposeClassPair(newClass)释放掉
```



#### 2、字典转模型

```objective-c
#import "NSObject+ModelFactory.h"
#import <objc/runtime.h>

@implementation NSObject (ModelFactory)

+ (instancetype)modelWithDict:(NSDictionary *)dict{
    
    id objc = [[self alloc] init];
    
    unsigned int count = 0;
    // 1.获取成员属性数组
    Ivar *ivarList = class_copyIvarList(self, &count);
    
    for (int i = 0;i < count;i++){
        Ivar ivar = ivarList[i];
        NSString *ivarName = [NSString stringWithUTF8String:ivar_getName(ivar)];
        NSLog(@"ivarName:%@",ivarName);
        
        // 2. model属性的变量名默认在前面加"_",所以此处去掉下划线"_"
        NSString *key = [ivarName substringFromIndex:1];
        NSLog(@"key:%@",key);
        
        id value = dict[key];
        
        // 获取成员属性类型
        NSString *ivarType = [NSString stringWithUTF8String:ivar_getTypeEncoding(ivar)];
        NSLog(@"ivarType:%@",ivarType);
        ivarType = [ivarType stringByReplacingOccurrencesOfString:@"@" withString:@""];
        ivarType = [ivarType stringByReplacingOccurrencesOfString:@"\"" withString:@""];
        
        // 二级转换,字典中还有字典,也需要把对应字典转换成模型
        // 判断下value,是不是字典
        if ([value isKindOfClass:[NSDictionary class]] && ![ivarType containsString:@"NS"]) {
            Class class = NSClassFromString(ivarType);
            if(class){
                value = [class modelWithDict:value];
            }
        }
        if (value) {
            [objc setValue:value forKey:key];
        }
    }
    return objc;
}

@end
  
//  注意：另外还要考虑到特殊字段的映射（比如id）、数组的映射
```



#### 3、方法交换

```objective-c
+ (void)load{
    Method orignalMethod = class_getInstanceMethod(self,@selector(viewDidLoad));
    Method newMethod = class_getInstanceMethod(self,@selector(newViewDidLoad));
    
    BOOL isAddMethod = class_addMethod(self, @selector(viewDidLoad), method_getImplementation(newMethod), method_getTypeEncoding(newMethod)); // class_addMethod 用于向类中动态添加一个新方法，如果方法已存在，则添加失败
    if (isAddMethod) {
        class_replaceMethod(self, @selector(newViewDidLoad), 
                                   method_getImplementation(originalMethod), 
                                   method_getTypeEncoding(originalMethod));
    }else{
        method_exchangeImplementations(orignalMethod,newMethod);
    }
}

- (void)newViewDidLoad{
    NSLog(@"newViewDidLaod");
  [self newViewDidLoad];
}

//tips：
// method_exchangeImplementations会把方法的imp（方法实现）交换。注意：并不会交换"方法缓存"中的imp，而是将方法缓存全部清空
// class_replaceMethod ：替换一个方法的方法实现
//如果是交换完方法之后还要继续执行被交换的方法实现，那么需要在新的方法实现中调用新的方法名，例如[self newViewDidLoad]

// 注意：不能在未调用 class_addMethod 之前执行 method_exchangeImplementations 
// ❌ 问题：如果当前类没有 viewDidLoad 实现，originalMethod 指向父类方法
// 这会导致父类的方法被替换，影响所有子类！
```

例子：工程中有些页面是不支持展示浮窗按钮，可以在UIVIewController的分类中 hook viewwillApplear ，在 hook 后的方法中判断当前控制器类名来做隐藏。

## 四、KVO

**概念**：key-value-observing，键值监听，可以用来监听某个对象的属性变化。

**本质**：重写原来的**setter**方法实现。

**原理**：

1. 利用 Runtime 动态生成一个子类 (**NSKVONotifying_XXX**)，并使实例对象的isa指针指向这个子类。（该子类的父类是原来的类**XXX**）

2. 当修改实例对象的属性时，会调用foundation的_NSSetXXXValueAndNotify函数(即重写setter的实现)：

   - willChangeValueForKey
   - 调用父类原来的setter实现
   - 调用didChangeValueForKey：内部会触发监听器（Observer）的监听方法（observerValueForKeyPath:ofObject:change:context:）

   ```objective-c
   //例子：
   void _NSSetXXXValueAndNotify ()
   {
       //1.willChangeValueForKey
   		[self willChangeValueForKey:@"age"];
   		//2.调用父类的setter方法
       [super setAge:age];
       //3.didChangeValueForKey
   		[self didChangeValueForKey:@"age"];
   }
   ```
   

**手动启动kvo（没有修改键值时也触发kvo）：**

```objective-c
//直接手动调用下面两个方法
[person willChangeValueForKey:@"age"];
[person didChangeValueForKey:@"age"]
```

**使用：**

```objective-c
//Person
@Property (nonatomic,copy)NSString *name;

//WJLViewController
@Property (nonatomic,copy)Person *person;
- (void)test{
		[self.person addObserver:self forKeyPath:@"name" options:NSKeyValueObservringOptionNew | NSKeyValueObservringOld context:@"name  changed"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject(id)object change:(NSDictionary <NSKevalueChangeKey,id> *)change context:(void *)context{
  
}

//注意observer需要释放
- (void)dealloc{
  	[self.person removeObserver:self forKeyPath:@"name"];
}
```

**KVO 与 KVC 的关系**

- **依赖关系**：KVO 依赖于 KVC
  - KVO 通知通过 KVC 机制触发
  - 直接修改实例变量不会触发 KVO，除非使用 KVC，即 _ivar = newValue 不会触发 kvo，但通过 setValue:forKey: 可以触发 kvo

## 五、KVC

**概念：**KVC（Key-Value Coding）是苹果提供的一种机制，允许开发者通过字符串（键）间接访问对象的属性和成员变量。它的核心方法是`valueForKey:`和`setValue:forKey:`。

**setValue:forKey:调用顺序**
// 假设调用 [obj setValue:value forKey:@"name"]

// 1. 查找 setter 方法（按优先级）
- (void)setName:(id)value;
- (void)_setName:(id)value;

// 2. 检查 accessInstanceVariablesDirectly
+ (BOOL)accessInstanceVariablesDirectly {
    return YES; // 默认返回YES，允许直接访问实例变量
    }

// 3. 查找实例变量（按优先级）
_name
_isName  
name
isName

**Tips：KVC可以触发KVO。**

**valueForKey:调用顺序**
// 假设调用 [obj valueForKey:@"name"]

// 1. 查找 getter 方法（按优先级）
- (id)getName;
- (id)name;
- (id)isName;        // 仅对 BOOL/int 等类型
- (id)_getName;
- (id)_name;

// 2. 查找 countOf<Key> 等集合方法
- (NSUInteger)countOfName;
- (id)objectInNameAtIndex:(NSUInteger)index;
// 如果找到，返回代理数组对象

// 3. 检查 accessInstanceVariablesDirectly

// 4. 查找实例变量（按优先级）
_name
_isName
name  
isName

## 六、category

分类是 Objective-C 用于**扩展类功能**的语法特性，允许在**不修改原类源码、不创建子类**的前提下，为已有类（包括系统类，如`NSString`、`NSArray`）添加新方法。
其核心价值：拆分复杂类的代码（按功能模块化）、复用扩展逻辑、轻量扩展系统类。

### 1、**本质：**

- Category编译之后的底层结构是struct category_t，里面存储着分类的对象方法、类方法、属性、协议信息
- 在程序运行的时候，runtime会将Category的数据合并到类信息中（类对象、元类对象中）
- 分类的实现原理是将category中的方法，属性，协议数据放在category_t结构体中，然后将结构体内的方法/属性/协议列表拷贝到类对象的对应列表中。 （插入最前面）

**如果类对象和分类对象有相同的方法实现，则会调用分类的方法实现，不会调用类对象里的方法实现。（类似重写，但其实是假的重写，因为类对象的方法实现并没有被抹去）**

**最后编译的分类，其方法列表会放在对应的类的methods的最前面，其他分类（类对象）的方法列表后移（类对象的方法列表会移到最后），这也是为什么同样的方法实现，会优先调用分类的方法实现，因为它在类的methods最前面。**

```objective-c
//类扩展（Extension和分类（Category）的区别：
/*
Extension：编译期就将对应的信息（属性、方法、协议等）合并到类（元类）对象中，相当于把公有的属性、方法私有化。
Category： 运行时将分类的信息（属性列表、方法列表、协议等）合并到类（元类）对象中。
*/
```

### 2、load

调用时机：load方法在**runtime**加载类、分类时被调用，且只调用一次，不管该类是否被调用/引用。

调用顺序：

1. 优先调用类的load

   a.先编译的类，先调用；

   b.先调用父类load，再调用子类load。

2. 再调用分类load

   按照编译顺序调用。

```c++
//解答：load方法底层调用是从一个loadable_classes数组中取类对象，然后取出类对象的load方法直接进行调用（(*load_method)(cls,SEL_load)）,而loadable_classes中类对象的存储顺序就是load的调用顺序；runtime加载类、分类时，会将类和分类添加到loadable_classes数组中，而且添加顺序是先添加其父类然后再添加本类，然后再按照编译顺序添加分类到loadable_classes中。所以，load的调用顺序如上所述。
```

**问题：为什么类对象的load方法没有被分类/子类取代？（即分类/子类实现了load方法，但是程序加载时类对象的load方法还可以被调用）**

```c++
//解答：load方法的调用是直接从对象中取出该函数指针，然后去调用，并不是通过objc_msgSend（objc_msgSend找到方法之后就不再继续找）。
load_method_t load_method = (load_method_t)classes[i].method;

//而其他的方法，则是通过下面方式去调用方法
objc_msgSend([XXX class],@selector(test));
//先找到对应的类（元类），然后从类（元类）方法列表里去取该方法，顺序为：分类->类；如果没找到该方法，则从类（元类）父类中寻找该方法...

//注意：手动调用load方法时（例如[person load]），调用顺序同objc_msgSend ，先从分类找，然后从子类找，然后再往上找父类...

```

load方法可以继承，但一般情况下不会手动去调用load方法，都是让系统自动调用。

### 3、initialize

调用时机：**类**第一次接受到消息的时候调用，例如[Person alloc]；调用机制是objc_msgSend。

调用顺序：先调用父类initialize（前提是父类没有调用过initialize），再调用子类initialize。

**initialize**和**load**方法区别：

- 调用时机不同。load是在runtime动态加载类对象的时候调用（只调用一次）；initialize是在类第一次接受消息时调用，每个类只会initialize一次（父类的initialize可能执行多次）

- 调用机制不同。load是直接找函数地址然后调用，只要类/分类实现了load，则所有的load方法都会被调用；initialize 遵循objc_msgSend 调用机制

- 调用顺序不同。

  load：1、a.先编译的类，先调用；b.先调用父类load，再调用子类load。2、再调用分类load（按照编译顺序调用）。

  initialize：1、先调用父类；2、再调用子类（如果子类没有实现initialize，则最终调用的是父类的initialize，因为遵循的是objc_msgSend机制）

### 4、关联对象

分类不能添加成员变量，但可以添加属性，并且可以通过关联对象的方式

利用的是runtime

分类里声明属性的话，只会生成getter和setter方法声明，不会生成成员变量和getter和setter方法实现！

但可以通过关联对象来实现getter和setter方法

```objective-c
//例如 ：在Person的Person+WJL分类里添加属性name
//.h文件声明属性 包含头文件 #import <objc/runtime.h>
@property (nonatomic,copy) NSString *name;

//.m文件声明get和set方法
- (void)setName:(NSString *)name{
  	/*
  	变量1：被关联的对象
  	变量2：通过一个key来进行关联，传的是指针，可以传@selector(name)，也可以传其他指针，例如const void *NameKey = &NameKey,然后传NameKey
  	变量3：关联对象的值
  	变量4：修饰符
  	修饰符（objc_AssociationPolicy）对应关系：
  	OBJC_ASSOCIATION_ASSIGN---assign
  	OBJC_ASSOCIATION_RETAIN_NONATOMIC---strong,nonatomic
  	OBJC_ASSOCIATION_COPY_NONATOMIC---copy,nonatomic
  	OBJC_ASSOCIATION_RETAIN---strong,atomic
  	OBJC_ASSOCIATION_copy---copy,atomic
  	*/
  	objc_setAssociatedObject(self,@selector(name),name,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)name{
  //_cmd为本方法地址（每个方法都默认会传self和_cmd两个参数）
  return objc_getAssociatedObject(self,_cmd);
}

//补充
//移除单个关联对象:将value传nil即可
objc_setAssociatedObject(id object,void *key,nil,objc_AssociationPolicy policy);
//移除所有关联对象：
objc_removeAssociatedObjects(id object);

```

**原理：**

关联对象并不是把属性放在类的属性列表中，而是存储在全局的统一的一个 AssociationsManager 中。



## 七、block

### 1、本质

- block是个oc对象，内部也有一个isa指针
- block内部封装了一段代码块以及代码块的调用环境

### 2、变量捕获

**auto**：自动变量，c语言函数默认在声明局部变量时，会默认用auto来修饰；其含义为：离开作用域会自动被销毁

例如：int age = 10;其实内部为 auto int age = 10；只不过auto可以省略，默认给添加了auto修饰。

| 变量类型 | 访问方式                           | 是否捕获到block内部          |
| -------- | ---------------------------------- | ---------------------------- |
| 局部变量 | auto：值传递<br />static：指针传递 | auto：捕获<br />static：捕获 |
| 全局变量 | 直接访问                           | 不捕获                       |

```objective-c
//例子
//1.局部变量：
int age = 10;
void (^blockName)(void) = ^{
		NSLog(@"age is %d",age);
};
age = 20;
blockName();//打印结果为10

//2.静态变量
static int age = 10;
void (^blockName)(void) == ^{
			NSLog(@"age is %d",age);
};

age = 20;
blockName();//打印结果为20

//3.全局变量
//定义全局变量 int age（注意：不是定义一个property属性）
age = 10;
void (^blockName)(void) = ^{
     NSLog(@"age is %d",age);
};
age = 20;
blockName();//打印结果为20
```

**说明：局部变量之所以被捕获到block内部，是因为block可能存在被跨函数访问的使用场景**。例如：

```objective-c
void (^blockName)(void);

- (void)test{
    int age  = 10;
    blockName = ^{
        NSLog(@"age is %d",age);
    };
    age = 20;
}

- (void)executeTest{
  	[self test];
  	blockName();//在block创建函数外调用block，由于block内部存在的变量是test函数的局部变量，所以需要block捕获局部变量到block内部，这样才可以使用该变量
}
```

问题1：下面的函数中，self会被blockName捕获吗？

```objective-c
- (void)test{
    void (^blockName)(void) = ^{
        NSLog(@"self is %@",self);
    };
}

//答案：会。因为每一个方法都默认包含两个参数：self和_cmd，参数为局部变量，局部变量会被捕获
```

问题2：下面的函数中，_name会被blockName捕获吗？

```objective-c
@property (nonatomic, copy) NSString *name;
- (void)test1{
    void (^blockName)(void) = ^{
        NSLog(@"name is %@",_name);
    };
}

- (void)test2{
    void (^blockName)(void) = ^{
        NSLog(@"name is %@",self.name);
    };
}

//答案：都会。因为self被捕获了，所以通过self获取的变量也相应的被捕获（注意区分【2.变量捕获】部分的例子中的第三种情况）
```

### 3、block的类型

block有三种类型，可以通过调用class方法或者isa指针查看具体类型，最终都是继承自NSBlock类型

- ____NSGlobalBlock____ (_NSConcreteGlobalBlock)：没有访问auto变量（局部变量）；对该类型的block进行copy，其类型不会有任何变换；**存放在.data区**
- ____NSStackBlock____(NSConcreteStackBlock)：访问了auto变量；**存放在栈上**
- ____NSMallocBlock____(NSConcreteMallocBlock)：____NSStackBlock____调用copy操作后变为MallocBlock类型；**存放在堆上**

### 4、block的copy

![block的copy](/Users/xiaozhuzhu/Documents/work/iOS资料/image/block的copy.png)

```objective-c
typedef void(^BlockName)(void);

BlockName block1() {
    return ^{
        NSLog(@"block1----");
    };
}

BlockName block2() {
    int age = 1;
    return ^{
        NSLog(@"block2----age:%d",age);
    };
}

- (void)blockClass{
    
    /*----Global类型----*/
    NSLog(@"GlobalClass : %@",[^{
        
    } class]);//__NSGlobalBlock__
    
    BlockName blo1 = block1();
    NSLog(@"blo1 class : %@",[blo1 class]);//__NSGlobalBlock__ 对Global类型的block，arc不会对其进行转换
    
    /*----Stack类型----*/
    int age= 1;
    NSLog(@"StackClass : %@",[^{
        NSLog(@"age : %d ",age);
    } class]);//__NSStackBlock__
    
    //以下四种情况ARC会将StackBlock类型转为MallocBlock类型
    //1.StackBlock作为返回值 ARC则将其转换为Malloc类型
    BlockName blo2 = block2();//block2内部的block为StackBlock类型，但block作为返回值时，ARC会将此block转为Malloc类型
    NSLog(@"blo2 class : %@",[blo2 class]);//__NSMallocBlock__
    
    //2.StackBlock被强引用(赋值给__strong指针时)
    BlockName blo3 = ^{
        NSLog(@"age : %d ",age);
    };
    NSLog(@"blo3 class : %@",[blo3 class]);
    
    //3.StackBlock被作为Cocoa API方法名中含有usingBlock的参数时
    NSArray *arr;
    [arr enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        
    }];
    
    //4.StackBlock被作为GCD API方法的参数时
    dispatch_async(dispatch_get_main_queue(), ^{
        
    });
}
```

### 5、block 的对象类型的 auto 变量

```objective-c
- (void)autoObj{
  //1.强引用
  Person *person = [[Person alloc] init];
  WJLBlock *block = ^{
			NSLog(@"person:%@",person);
  };
  //block内部结构体为：
  struct __autoObj_block_imp_0{
    struct __bloc_impl impl;
    struct __autoObj_block_desc_0* Desc;//用来描述block的一些参数，比如block的size
    Person *__strong person;//指向person对象 强引用
  }
    
  //2.弱引用
  Person *p = [[Person alloc] init];
  __weak Person *weakPerson = p;
  WJLBlock *block = ^{
			NSLog(@"weakPerson:%@",weakPerson);
  };
  //block内部结构体为：
  struct __autoObj_block_imp_0{
    struct __bloc_impl impl;
    struct __autoObj_block_desc_0* Desc;//用来描述block的一些参数，比如block的size
    Person *__weak person;//指向person对象 弱引用
  }
}
```

![block对象类型的auto变量](/Users/xiaozhuzhu/Documents/work/iOS资料/image/block对象类型的auto变量.png)

![访问对象类型auto变量block结构体中desc结构体](/Users/xiaozhuzhu/Documents/work/iOS资料/image/访问对象类型auto变量block结构体中desc结构体.png)

```objective-c
- (void)yinyong{
    
    //栈区的block对auto变量（局部变量）引用都是弱引用
    //堆区的block对auto变量引用区分强引用和弱引用
    
    /*----堆区block----*/
  
  	//1.强引用
    BlockName block;
    {
        BlockTest1 *bloT1 = [[BlockTest1 alloc] init];
        bloT1.name = @"strong obj";
        block = ^{
            NSLog(@"bloT1.name:%@",bloT1.name);
        };
    }//block内部是对bloT1进行强引用，所以在执行完此处花括号里的代码后，bloT1并未被释放
    //上面的^{ NSLog(@"bloT1.name:%@",bloT1.name);}被block强引用，所以内存在堆区;
    NSLog(@"------");
 
    //2.弱引用
    BlockName block2;
    {
        BlockTest1 *bloT2 = [[BlockTest1 alloc] init];
        bloT2.name = @"weak obj";
      
        __weak BlockTest1 *weakBloT = bloT2;

        block2 = ^{
            NSLog(@"bloT2.name:%@",weakBloT.name);
        };
    }//因为bloT2弱引用，执行完此处花括号里的代码，bloT2就被释放
    
    NSLog(@"-----");
    
}
```

### 6、在block内部修改外部变量

方法：

1. 使用静态变量
2. 使用全局变量
3. __block修饰局部变量（无法修饰静态、全局变量）

#### 1、__block修饰基本数据类型

```objective-c
- (void)blockT{
  		__block int age = 10;
  		WJLBlock block = ^{
        	age = 20;
      };
}
```

![__block修饰符](/Users/xiaozhuzhu/Documents/work/iOS资料/image/__block修饰符.png)

上图被__block修饰的age的地址值和被包装的Block_byref_age_0对象中的age地址值是同一个。

#### 2、__block 修饰对象类型数据

```objective-c
- (void)blockT{
	  __block Person *person = [Person alloc] init];
  	WJLBlock block = ^{
      	NSLog(@"Person :%@",person);
    };
}

//block结构体
struct __blockT_block_impl_0{
  	struct __block_impl impl;
  	struct __blockT_block_desc_0* Desc;
    __Block_byref_person_0 *person;//强引用（retain）
};
//__Block_byref_person_0结构体
struct __Block_byref_person_0{
  	void *__isa;
    __Block_byref_person_0 *forwarding;//指向本结构体
    int __flags;
    int __size;
    void (*__Block_byref_id_object_copy)(void*,void*);//如果__block修饰基本数据类型，则结构体中不含该值，因为不存在对基本数据类型的引用
    void (*__Block_byref_id_object_dispose)(void*);//如果__block修饰基本数据类型，则结构体中不含该值，因为不存在对基本数据类型的引用
	  Person *__strong person;//强引用（retain），指向person对象；如果block内部的person为__weak修饰，则此处为Person *__weak person，即弱引用;（注意：仅限于ARC会retain，如果是MRC环境下，不会retain）
};  

```

使用__block修饰局部变量为何可以在block内部被修改？原理：

**编译器会将__block修饰的局部变量包装成一个对象，并且该对象被block持有，block可以通过该对象的指针对对象进行修改。**

### 7、__block内存管理

**1、当block在栈上时，都不会对__block修饰的变量进行强引用**

**2、当被block被copy到堆上时**

- 会调用block内部的copy函数
- copy函数内部调用_Block_object_assign函数
- _Block_object_assign函数会对__block修饰的变量形成**强引用**（retain）

  ```objective-c
  __block Person *person = [Person alloc] init];
  //block结构体
  struct __blockT_block_impl_0{
    	struct __block_impl impl;
    	struct __blockT_block_desc_0* Desc;
      __Block_byref_person_0 *person;//强引用（retain）,上面说的强引用是对__Block_byref_person_0的强引用
  };
  //具体对person对象(注意不是_Block_byref_person_0)是否强引用，要看block内部是weakPerson还是person。见6.2部分
  ```


2、当block被移除时

- block内部调用dispose函数
- dispose函数内部调用_Block_object_dispose函数
- _Block_object_dispose函数内部会自动**释放__block对象**（release）

**tips：结合第5条“对象类型的auto变量”记忆**。

### 8、循环引用

指针互相强引用导致循环引用。

```objective-c
- (void)cycle{
  	Person *per = [[Person alloc] init];
  	per.block = ^{
				NSLog(@"person.name:%@",per.name);
    };
  //上述代码存在循环引用，person被block强引用，block又被person强引用，导致循环引用，内存泄漏。可以改为下面的代码
  
  //一、ARC中可以用以下3个方案解决block循环引用
  //方法1：__weak
  Person *per = [[Person alloc] init];
  __weak typeof(per)weakPer = per;
  per.block = ^{
	    NSLog(@"person.name:%@",weakPer.name);
  };
  //这样就不会循环引用，因为block弱引用了person，当person释放时，block也被释放了
  
  //方法2：_unsafe_unretained
   Person *per = [[Person alloc] init];
   _unsafe_unretained typeof(per)weakPer = per;
   per.block = ^{
			NSLog(@"person.name:%@",weakPer.name);
   };
  
  //__weak：弱引用，指向的对象被销毁时，会自动让指针指向nil
  //__unsafe_unretained：弱引用，不安全，指向对象被销毁时，指针的地址值不变（野指针）；不建议使用
  
  //方法3：__block 
   __block Person *per = [[Person alloc] init];
   per.block = ^{
			NSLog(@"person.name:%@",per.name);
      per = nil;
   };
  per.block();
  //方法3缺点是必须执行block，进而内存释放不及时
  
  //二、MRC中可以用以下2个方案解决block循环引用
  //MRC不支持__weak
  //方法1：使用_unsafe_unretained，同ARC
  //方法2：使用__block，MRC中，block不会对__block修饰的person产生强引用
  __block Person *per = [[Person alloc] init];
   per.block = [^{
			NSLog(@"person.name:%@",per.name);
   } copy];
	[per release];
}

```

### 9、问题

1、block原理是什么，本质是什么？

答：block封装了函数调用以及调用环境，它的本质是个oc对象。

2、__block的作用是什么？

答：解决无法在block内部修改变量的问题；编译器会把__block变量封装成一个对象，该对象中也存储了被修改的对象指针，block可以根据指针找到该对象，并对其进行修改。

3、block为什么使用copy？注意事项？

block不进行copy就不会存储在堆上，程序员就无法掌控它的内存，也不能完全安全的对其进行操作。（也可以使用strong）

注意不要循环引用。

4、block在修改NSMutableArray时，需要__block吗？

不需要！

## 八、内存管理

### 1、CADisplayLink和NSTimer

基于runloop实现的定时器，如果runloop的任务过重，那么定时器则**不准时**，所以这两种定时器并**不准时**

两者要注意防止循环引用

```objective-c
@property (nonatomic,copy)CADisplayLink *link;
@property (nonatomic,copy)NSTimer *timer;

//CADisplayLink：不用传时间，它和屏幕刷新帧率同步，例如60FPS、120FPS
self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector:(displayLinkTest)];
[self.link addRunLoop:[NSRunLoop mianRunLoop] forMode:NSDefaultRunLoopMode];

self.timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(timerTest) userInfo:nil repeats:YES];
//scheduledTimerWithTimeInterval会自动将timer添加到runLoop

// 内存泄漏：以上两种方式会导致循环引用，定时器被self强引用，self又被定时器强引用，导致self和定时器都无法释放内存，进而导致内存泄漏
// 注意：当NSTimer的repeat参数设置为NO，表示这是一个一次性计时器，在其运行结束之后，计时器会自动调用invalidate方法，从而取消对目标的强引用。所以，一次性计时器不需要显示地停止。当计时器触发事件后，它会自动使自己失效，从而释放对目标的强引用。因此，如果你的NSTimer的repeat参数设置为NO，那么你不需要担心内存泄漏问题。

//解决方案：
//方案1：NSTimer使用block的创建方式
__weak typeof(self) weakSelf = self;
self.timer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){
  	[weakSelf timerTest];
}];

//方案2：使用中间变量作为target，让中间变量弱引用self；
self.timer = [NSTimer scheduledTimerWithTimeInterval:1 target:[WJLProxy proxyWithTarget:self] selector:@selector(timerTest) userInfo:nil repeats:YES];

//声明一个继承自NSProxy的类WJLProxy，然后声明一个弱引用的target属性
//NSObject也是基类，NSProxy也是基类，它俩没有继承关系
//NSProxy是专门做消息转发的类
@property (nonatomic,weak)id target;

+ (instancetype)proxyWithTarget:(id)target{
  WJLProxy *proxy = [WJLNSProxy alloc];//NSProxy的初始化不需要init，它没有init方法
  proxy.target = target;
  return proxy;
}
//因为这个中间变量WJLProxy并没有timer里传入的selector的方法实现，所以在这里要做一下消息转发处理
//NSProxy是专门做消息转发的类，如methodSignatureForSelector果在它的类里没有找到方法，会直接走下面消息转发，不会从父类里搜索方法，因为它父类里没有方法；效率较高
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selctor{
   return [self.target methordSignatureForSelector:selctor];
}

- (void)forwardInvocation:(NSInvocation *)invocation{
  [invocation invokeWithTarget:self.target];
}

//方案3：和方案2的处理方法大致相同，区别在于把继承自NSProxy的类改为集成NSObject
+ (instancetype)proxyWithTarget:(id)target{
  WJLObject *wjlObj = [[WJLObject alloc] init];
  wjlObj.target = target;
  return wjlObj;
}

//因为这个中间变量WJLObject并没有timer里传入的selector方法实现，所以在这里要做一下消息转发处理
- (id)forwardingTargetForSelector:(SEL)selctor{
			return self.target;
}

//方案2和方案3的区别：
//1.方案2继承自NSProxy，效率更高，因为它不会从父类里搜索方法，只要本类中没有方法，则直接走消息转发；
//2.方案3继承自NSObject，如果本类里找不到方法，它会一级一级的从父类里去找方法，都找不到之后，再走消息转发，效率低；
//建议使用方案2
```

### 2、GCD定时器

**GCD定时器是基于系统内核，不是基于runloop，不存在不准时的情况！**

```objective-c

- (void)test
{
    // 队列
    //dispatch_queue_t queue = dispatch_get_main_queue();
    
    dispatch_queue_t queue = dispatch_queue_create("timer", DISPATCH_QUEUE_SERIAL);
    
    // 创建定时器
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    
    // 设置时间
    uint64_t start = 2.0; // 2秒后开始执行
    uint64_t interval = 1.0; // 每隔1秒执行
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, start * NSEC_PER_SEC),
                              interval * NSEC_PER_SEC, 0);
    
    // 设置回调
    //    dispatch_source_set_event_handler(timer, ^{
    //        NSLog(@"1111");
    //    });
    dispatch_source_set_event_handler_f(timer, timerFire);
    
    // 启动定时器
    dispatch_resume(timer);
    
    self.timer = timer;
}

void timerFire(void *param)
{
    NSLog(@"2222 - %@", [NSThread currentThread]);
}

```

基于GCD封装一个定时器

```objective-c
#import "MJTimer.h"

@implementation MJTimer

static NSMutableDictionary *timers_;
dispatch_semaphore_t semaphore_;
+ (void)initialize
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        timers_ = [NSMutableDictionary dictionary];
        semaphore_ = dispatch_semaphore_create(1);
    });
}

+ (NSString *)execTask:(void (^)(void))task start:(NSTimeInterval)start interval:(NSTimeInterval)interval repeats:(BOOL)repeats async:(BOOL)async
{
    if (!task || start < 0 || (interval <= 0 && repeats)) return nil;
    
    // 队列
    dispatch_queue_t queue = async ? dispatch_get_global_queue(0, 0) : dispatch_get_main_queue();
    
    // 创建定时器
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    
    // 设置时间
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, start * NSEC_PER_SEC),
                              interval * NSEC_PER_SEC, 0);
    
    
    dispatch_semaphore_wait(semaphore_, DISPATCH_TIME_FOREVER);
    // 定时器的唯一标识
    NSString *name = [NSString stringWithFormat:@"%zd", timers_.count];
    // 存放到字典中
    timers_[name] = timer;
    dispatch_semaphore_signal(semaphore_);
    
    // 设置回调
    dispatch_source_set_event_handler(timer, ^{
        task();
        
        if (!repeats) { // 不重复的任务
            [self cancelTask:name];
        }
    });
    
    // 启动定时器
    dispatch_resume(timer);
    
    return name;
}

+ (NSString *)execTask:(id)target selector:(SEL)selector start:(NSTimeInterval)start interval:(NSTimeInterval)interval repeats:(BOOL)repeats async:(BOOL)async
{
    if (!target || !selector) return nil;
    
    return [self execTask:^{
        if ([target respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [target performSelector:selector];
#pragma clang diagnostic pop
        }
    } start:start interval:interval repeats:repeats async:async];
}

+ (void)cancelTask:(NSString *)name
{
    if (name.length == 0) return;
    
    dispatch_semaphore_wait(semaphore_, DISPATCH_TIME_FOREVER);
    
    dispatch_source_t timer = timers_[name];
    if (timer) {
        dispatch_source_cancel(timer);
        [timers_ removeObjectForKey:name];
    }

    dispatch_semaphore_signal(semaphore_);
}

@end

```

### 3、iOS内存布局

**用户空间**包含：

1. **代码区（Text Segment）**：存储程序二进制代码（函数 / 方法实现），只读（防止篡改）
2. **常量区**：**只读的常量空间**，字符串常量（如 `@"iOS Memory"`）、`const` 修饰的常量（如 `const int constVar = 5;`）。
3. **全局静态区（Data Segment）**：**贯穿程序生命周期的空间**；存储应用程序的**全局变量**和**静态变量**，这个部分还可以被分为**已初始化的数据段**和**未初始化的BSS段**。这个部分的内存在程序启动时被分配，并在程序运行期间保持不变。
4. **堆（Heap）**：在程序运行时动态分配的内存空间，例如通过**alloc**、**new**、**malloc**初始化的对象。堆中的内存需要手动管理（ARC除外），未使用的内存必须被手动释放（ARC除外），否则会造成内存泄漏。
5. **栈（Stack）**：存储内容**：局部变量（如 `int a`、`NSString *ptr`）、函数参数、函数返回值。
   ✅ 注意：对象的**指针**存在栈，对象**本身**存在堆（如 `NSString *obj = [[NSString alloc] init]`，`obj` 指针在栈，`alloc` 出来的对象在堆）。

地址分配**由低到高**分别是：代码区 - > 数据段 - > BSS 段 - >  堆 - > 栈

**内核空间**：包含内核代码和数据，以及硬件设备的内存映射等。

注意：宏定义并不占用特定的内存区域，而是在预处理阶段进行文本替换，最终被包含在生成的可执行文件中。

```objective-c
int age = 24;//全局初始化区（数据区），数据段
NSString *name;//全局未初始化区（BSS区），数据段
static NSString *sName = @"Dely";//全局（静态初始化）区，数据段

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    int tmpAge;//栈
    NSString *tmpName;//栈
    NSString *number = @"123456"; //123456在常量区，number在栈上。
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:1];// 分配而来的8字节的区域就在堆中，array在栈中，指向堆区的地址
    NSInteger total = [self getTotalNumber:1 number2:1];
}

- (NSInteger)getTotalNumber:(NSInteger)number1 number2:(NSInteger)number2{
    return number1 + number2;//number1和number2 栈区
}
@end
```



### 4、内存管理-MRC

```objective-c
// 例子：手写一个属性
// Person.h
{
  Dog *_dog;
}

- (Dog *)dog;
- (void)setDog:(Dog *)dog;

//Person.m
- (void)setDog:(Dog *)dog{
    if(_dog != dog){
      [_dog release];//先将之前赋值的dog release掉
      _dog = [dog retrain];
    } 
}
- (Dog *)dog{
  return _dog;
}

- (void)dealloc{
  [_dog release];
  _dog = nil;
  [super dealloc];
}

//外部调用person
- (void)test{
 		Dog *dog1 = [[Dog alloc] init];//dog1 retaincount: 1
   	Dog *dog2 = [[Dog alloc] init];//dog2 retaincount: 1
  
  	Person *person = [Person alloc] init];//person retaincount : 1
  
    [person setDog:dog1];//dog1 retaincount: 2
  	[person setDog:dog2];//dog2 retaincount: 2 ；dog1 retaincount: 1(setDog中有release一次)
  
    [dog1 release];//dog1 retaincount: 0
    [dog2 release];//dog2 retaincount: 1
    [person release];//person retaincount : 0；dog2 retaincount: 0(person的dealloc中有release一次)
}

//注意：基本数据类型就不用手动管理其内存，即不用调用retain 或 release
```

- 在iOS中使用引用计数来进行内存管理
- 一个新创建的oc对象，引用计数为1，当引用计数为0时，对象被销毁，其内存被释放
- 调用retain会使引用计数+1，调用release会使引用计数-1
- 内存管理经验：

1. 当调用alloc、new、copy、mutableCopy返回一个新对象时，引用计数+1，在不需要该对象时，要调用release或autorelease进行释放
2. 想拥有某个对象时，就让它引用计数+1，不想拥有时，就让它引用计数-1

- 可以通过私有api查看自动释放池的情况

exten void _objc_autoreleasePoolPrint(void);

![copy-mutableCopy](/Users/xiaozhuzhu/Documents/work/iOS资料/image/copy-mutableCopy.png)

### 5、weak指针的实现原理

对象会将弱引用存到一个叫做“weak table”的哈希表里，以对象的地址为 key，value 是这个对象的 weak 指针的地址集合。当对象要销毁时，runtimer 会取出其中的weak table，把里面存储的弱引用的空间释放，并将他们的指针置为 nil。

### 6、自动释放池 autoreleasepool

自动释放池是 iOS 中用于管理对象生命周期的内存管理机制，核心作用是**延迟释放 “自动释放对象”**：通过 `@autoreleasepool` 代码块定义作用范围，在此范围内被标记为 `autorelease` 的对象会被加入池中，当代码块结束（池销毁）时，池会对内部所有对象统一发送 `release` 消息，实现内存的自动回收。

“延迟释放”，是因为被加入自动释放池的对象，**不会在调用 `autorelease（ARC 下 autoreleasePool 内创建对象时默认调用 autorelease）` 的瞬间被释放**：比如你调用 `[obj autorelease]` 时，对象只是被 “暂存” 到池中，释放行为会被 “延迟” 到池销毁的时机（比如 `@autoreleasepool` 代码块结束、主线程 RunLoop 循环结束），此时池才会统一遍历内部对象并发送 `release` 消息。

```objective-c
// 开发者编写的代码
@autoreleasepool {
    // 自动释放对象的操作
}

// 编译器转换后的等效代码（伪代码）
void *token = objc_autoreleasePoolPush(); // 创建池，返回令牌
{
    // 自动释放对象的操作
}
objc_autoreleasePoolPop(token); // 销毁池，释放对象
```

#### 1. AutoreleasePoolPage

来管理 autoreleasepool 里的对象，每个 AutoreleasePoolPage 占 4096 个字节，除了存放自己内部的成员变量，剩余的空间用来存放autorelease 对象的地址。每个 autoreleasepool 里可能有多个  AutoreleasePoolPage，因为 pool 内的 autorelease 对象可能有多个，导致一个 page 存储不下那么多对象

```objective-c
//AutoreleasePoolPage内部结构：
  magic_t magic;//地址值为0x1000
  id *next;
  pthread_t thread;//当前autoreleasepool的线程
  AutoreleasePoolPage *parent;//指向上一个page（每个autoreleasepool里可能有多个autoreleasepoolpage，因为pool内的autorelease对象可能有多个，导致一个page存储不下那么多对象）
	AutoreleasePoolPage *child;//指向下一个page
  uint32_t depth;
  uint32_t hiwat；//截至到此处，AutoreleasePoolPage里的所有成员变量占用7*8=56个字节
  ...//存放POOL_BOUNDARY地址,地址值为0x1038（边界地址值）
  ...//存放autorelease对象，例如person1
  ...//存放autorelease对象；例如person2（最后一位地址值为0x2000）
//相当于一个page可以存储4096-56=4040个字节的对象


//多个AutoreleasePoolPage通过双向链表链接在一起
//page1->page2->page3（通过child指针，page3的child指针为空）
//page1<-page2<-page3（通过parent指针，page1的parent指针为空）
    
```

autoreleasepool 只要调用调用 autoreleasepoolpush （创建池）的操作，首先会让一个 POOL_BOUNDARY 的值入栈，并返回该值的地址值。

```objective-c
//1
int main(int argc, char * argv[]) {
    @autoreleasepool {
        Person *person = [[[Person alloc] init] autorelease];//autoreleasepoolpage会拿出8个字节来存放person对象
    }
    
//上面pool的代码相当于下面代码
    autoreleasepoolobj = autoreleasepoolpush();
    autoreleasepoolobj = 0x1038;
    Person *person = [[[Person alloc] init] autorelease];//autoreleasepoolpage会拿出8个字节来存放person对象
    autoreleasepoolpop(0x1038)//从最后面的一个对象开始释放，一直释放到此处，代表该pool内的对象全部释放完毕
}

//2
//多个releasepool嵌套
@autoreleasepool {//调用push POOL_BOUNDARY入栈
        Person *person1 = [[[Person alloc] init] autorelease];//autoreleasepoolpage会拿出8个字节来存放person对象
        @autoreleasepool {//调用push POOL_BOUNDARY入栈
             Person *person2 = [[[Person alloc] init] autorelease];//autoreleasepoolpage会拿出8个字节来存放person对象
             @autoreleasepool {//调用push POOL_BOUNDARY入栈
                Person *person3 = [[[Person alloc] init] autorelease];//autoreleasepoolpage会拿出8个字节来存放person对象
             }//调用pop
        }//调用pop
}//调用pop

//上面的pool内一共有一个page，一个page里有三个POOL_BOUNDARY入栈。

```

`POOL_BOUNDARY` 是一个特殊的空指针（`nil`），其核心作用是**标记一个自动释放池的 “起始边界”**。当创建一个自动释放池时（无论是外层还是内层），系统会在当前 `AutoreleasePoolPage` 中插入一个 `POOL_BOUNDARY`，作为这个池的 “起点”。

例如，嵌套的自动释放池会产生多个 `POOL_BOUNDARY`：

```objective-c
// 外层自动释放池
@autoreleasepool { 
    // 插入 外层 POOL_BOUNDARY（标记外层池的起点）
    id obj1 = [NSObject new];
    [obj1 autorelease]; // 加入外层池
    
    // 内层自动释放池
    @autoreleasepool { 
        // 插入 内层 POOL_BOUNDARY（标记内层池的起点）
        id obj2 = [NSObject new];
        [obj2 autorelease]; // 加入内层池
    } 
    // 内层池销毁时，从当前栈顶遍历到“内层 POOL_BOUNDARY”，释放 obj2
} 
// 外层池销毁时，从当前栈顶遍历到“外层 POOL_BOUNDARY”，释放 obj1
```

在这个例子中：

- 外层池创建时，插入**第一个 `POOL_BOUNDARY`**（外层边界）；
- 内层池创建时，插入**第二个 `POOL_BOUNDARY`**（内层边界）；
- 两个 `POOL_BOUNDARY` 共同存在于 `AutoreleasePoolPage`（或其链表）中，用于区分不同池的范围。

**关键结论：**

- **每个自动释放池（无论内外层）都对应一个独立的 `POOL_BOUNDARY`**，用于标记自身的边界；
- 嵌套的自动释放池会产生多个 `POOL_BOUNDARY`，数量等于嵌套的池层数；
- 释放时，系统通过查找 “当前池对应的 `POOL_BOUNDARY`” 来确定释放范围，确保只释放当前池内的对象，不影响其他池。

因此，“自动释放池” 与 `POOL_BOUNDARY` 是**一一对应**的关系，有多少个 `@autoreleasepool` 代码块，就会有多少个 `POOL_BOUNDARY`。

#### 2、MRC中调用autorelease的对象什么时候释放

对象什么时候调用release，和当前的runloop有关；对象可能在某次的runloop循环中，**runloop休眠前**调用release。

#### 3、ARC中局部变量在变量所在方法执行完之后会立马释放

```objective-c
- (id)transformResponse:(LxCoreContact_PhoneCall_QueryResponse *)response mTime:(int64_t)mTime{
        
    @autoreleasepool {
          for (LxCoreContact_PhoneCall_Contact *contact in opArr) {
             UIImage *img = [UIImage new];
          }
      }
 	  NSLog(@"结束");
  	return id;
}
```

1. **加上 `@autoreleasepool` 时**

- 代码中的 `UIImage *img = [UIImage new];` 创建的对象，会被加入到当前的自动释放池（即这个 `@autoreleasepool` 块对应的池）。
- 当 `@autoreleasepool` 块执行结束（即 `}` 处），系统会自动向池中的所有对象发送 `release` 消息。
- 如果这些对象的引用计数变为 0，就会立即被释放（销毁）。

在你提供的代码中，`UIImage` 对象会在 `for` 循环结束、`@autoreleasepool` 块退出时被释放（前提是没有其他强引用）。

2. **不加 `@autoreleasepool` 时**

- `UIImage` 对象会被加入到**当前线程的默认自动释放池**中（通常是主线程的 RunLoop 自动创建的池）。
- 默认自动释放池的释放时机与 RunLoop 周期相关：
  - 在主线程中，通常会在每次 RunLoop 迭代结束时（例如一次事件循环完成后）释放池中的对象。
  - 具体来说，可能是在方法执行完毕、返回到调用者之后，等待下一次 RunLoop 周期结束时才释放。

这种情况下，`UIImage` 对象的释放会延迟到当前 RunLoop 周期结束，而不是在 `for` 循环结束后立即释放。

### 总结

- 加 `@autoreleasepool`：对象在块结束时立即释放，适合在循环中创建大量临时对象的场景（避免内存峰值过高）。
- 不加 `@autoreleasepool`：对象延迟到当前 RunLoop 周期结束时释放，由系统默认池管理。

### 7、补充知识点

32位"和"64位"这两个术语通常用来描述计算机中的两个主要概念：指令集架构和操作系统。

1. **指令集架构（Instruction Set Architecture，ISA）**：ISA是计算机硬件和软件之间的接口，定义了各种不同的操作码（也就是指令），以及CPU（中央处理器）对这些指令的解释。在这个上下文中，32位和64位主要描述的是**CPU一次可以处理的数据的宽度**。例如，32位架构的CPU一次可以处理32位（也就是4字节）的数据，而64位架构的CPU一次可以处理64位（也就是8字节）的数据。此外，这也影响了CPU可以**直接访问的内存空间的大小**。32位系统最多可以直接访问4GB的内存，而64位系统可以直接访问的内存理论上可达到18.4亿GB。
2. **操作系统（Operating System，OS）**：操作系统管理计算机硬件和软件资源，提供各种服务给软件应用。在这个上下文中，32位和64位主要描述的是操作系统对数据的处理宽度和可以支持的内存大小。32位操作系统通常最多支持4GB内存，而64位操作系统可以支持更多的内存。

在现代计算机中，64位架构已经变得非常普遍，因为它们可以支持更大的内存空间，并且可以更有效地处理大量的数据。



## 九、性能优化

### 1、CPU和GPU

![cpu+gpu](/Users/xiaozhuzhu/Documents/work/iOS资料/image/cpu+gpu.png)

### 2、屏幕成像原理

显示器会首先发送一个垂直信号（VSync），代表开始成像，然后再一行一行的发送水平信号（HSync），一行一行的将数据展示出来；渲染下一帧时，则再发送一个垂直信号，然后再一行行的发送水平信号。

![屏幕成像原理](/Users/xiaozhuzhu/Documents/work/iOS资料/image/屏幕成像原理.png)

### 3、卡顿产生的原因

当CPU和GPU处理、渲染数据时间过长，就会导致在垂直信号（VSync）到来的时候（刷帧），数据还未渲染到屏幕上，这时，屏幕上显示的还是上一帧的数据。这就导致卡顿现象的出现。

![卡顿产生的原因](/Users/xiaozhuzhu/Documents/work/iOS资料/image/卡顿产生的原因.png)

如果按照60FPS的刷帧率，也就是说1s中刷新60帧，那么，每搁16.7ms就会有一次VSync信号。也就是说CPU和GPU的处理总时长要低于16.7ms。

### 4、性能优化

#### 1、CPU

#### 2、GPU

##### 离屏渲染

**概念：**指 GPU 或 CPU 在当前屏幕缓冲区之外，额外开辟一块内存区域进行渲染操作，完成后再将结果合并到当前屏幕缓冲区的过程。

**为什么会产生离屏渲染？**

正常的渲染流程是 **“当前屏幕缓冲区直接渲染”**：GPU 直接在用于显示的帧缓冲区（Frame Buffer）中绘制内容，效率极高。
但当视图的渲染需求无法直接在当前帧缓冲区完成时，系统会触发离屏渲染，例如：

- 需要临时存储中间渲染结果（如多层视图叠加的最终效果）；
- 渲染操作复杂，需分步处理（如添加特殊图层效果）。

**触发离屏渲染的常见场景**

1. **图层特殊效果**：
   - 圆角（`cornerRadius` + `masksToBounds = YES`，仅当图层有背景色或图片时触发）；
   - 阴影（`shadowPath` 未设置时，系统需计算图层轮廓，触发离屏渲染）；
   - 遮罩（`mask` 属性，需合并遮罩层和内容层）；
   - 透明度动画（`opacity < 1` 且图层有子图层时，可能触发）。
2. **绘制相关**：
   - 重写 `drawRect:` 方法（CPU 离屏渲染，手动绘制内容到临时缓冲区）；
   - 使用 `UIBezierPath` 绘制复杂图形并设置为图层内容。
3. **其他情况**：
   - 图层的 `shouldRasterize = YES`（强制开启离屏渲染并缓存结果）；
   - 某些滤镜效果（`CIFilter`）。

**离屏渲染的优缺点**

- **优点**：解决了复杂渲染场景的分步处理问题，支持更丰富的视觉效果。
- **缺点：**
  - **性能损耗**：额外的内存开辟、渲染操作和缓冲区合并会消耗 GPU/CPU 资源，频繁触发可能导致卡顿（尤其是滚动列表场景）；
  - **内存占用**：离屏渲染的缓冲区需占用内存，过多时可能引发内存警告。

**优化建议**

1. **避免不必要的特殊效果**：
   - 圆角优化：用图片直接切圆角，或通过 `CAShapeLayer` + `UIBezierPath` 绘制（性能优于 `cornerRadius`）；
   - 阴影优化：指定 `shadowPath` 明确阴影轮廓，避免系统自动计算。
2. **合理使用光栅化（`shouldRasterize`）**：
   - 仅对静态内容开启（如固定不变的复杂视图），动态内容会因频繁重建缓存导致性能下降；
   - 配合 `rasterizationScale` 设置正确的缩放比例（通常为屏幕 scale），避免模糊。
3. **减少 `drawRect:` 调用**：
   - 优先使用系统控件或图层属性实现效果，避免手动绘制；
   - 若必须重写，避免在其中执行复杂计算。

### 5、耗电优化

#### 1、耗电来源

1. CPU处理事情
2. 网络请求
3. 定位
4. GPU图像处理

#### 2、耗电优化

## 6、APP的冷启动优化

### 1、APP的启动

### 2、APP的冷启动优化

1. 减少动态库的使用，在需要的时候再去加载或初始化第三方的SDK；
2. 尽量减少类、分类的数量，定期清理不必要的类、分类
3. 尽量避免在类的load、appdelegate的didfinishLaunching方法里执行复杂操作，
4. 资源和操作在用到的时候才去加载，比如懒加载控件
5. 优化启动时的代码逻辑，去除冗余代码
6. 缓存下次启动时需要的数据，避免下次启动时重复的网络请求
7. 启动图的设计尽量简洁、轻量级，避免一些复杂动画的使用

冷启动时间：设置



## 十、安装包瘦身

1. 移除无用资源文件，比如图片、音频、视频

2. 移除无用的代码、库，重复代码可以复用

3. 优化图片资源，这部分可以让设计来做

4. 动态加载一些资源文件，比如在需要的时候再去从服务端下载一些资源文件，比如王者荣耀安装后，再打开需要下载一些资源文件

5. 使用位码（Bitcode），启用Bitcode后， Xcode 会将程序编译为一个中间表现形式( bitcode )，APP Store将Bitcode编译为64或32位程序，APP Store会根据设备和架构来下发指定位数的程序

6. APP Thinning技术（其实包含了Bitcode的操作），可以根据设备和架构减小APP的安装包大小，仅下载必须的资源，比如图片资源（@2x或@3x）

7. 使用动态库，同一动态库只会被系统加载一次，多个程序可以共用一套动态库

   

![安装包瘦身工具](/Users/xiaozhuzhu/Documents/work/iOS资料/image/安装包瘦身工具.png)

## 十一、架构设计

### 1、MVC

**苹果版MVC：** view和model分离，controller拿model的数据展示在view上

优点：view和model互相分离，两者都可以重复利用

缺点：viewcontroller过于臃肿



**变种MVC**：view依赖model，view的赋值操作在自己本类中进行

优点：controller代码会有少量减少

缺点：view依赖model，导致view使用的时候，必须使用model


MVVM和MVP的区别：

MVVM可以让view去持有viewModel，并且监听viewModel的属性值变化，当viewModel的属性值改变时，view去刷新视图

### 4、三/四层架构

![三层架构](/Users/xiaozhuzhu/Documents/work/iOS资料/image/三层架构.png)

![四层架构](/Users/xiaozhuzhu/Documents/work/iOS资料/image/四层架构.png)

### 5、设计模式

主要是类与类之间的交互模式。

常用的四种模式：

1. **单例模式**：Singleton模式确保一个类只有一个实例，并提供一个全局访问点来获取该实例。在iOS中，单例模式常用于全局共享的对象，例如应用程序配置、网络管理等。
2. **工厂模式**：Factory模式通过一个工厂类来创建和管理对象的实例，将对象的创建与使用分离，提供了一种灵活的对象创建方式。在iOS中，常见的应用场景是通过工厂方法来创建视图控制器实例。
3. **代理模式**：Delegate模式通过委托对象将一部分功能委托给其他对象实现。在iOS开发中，Delegate模式常用于控制器之间的通信、事件处理等场景。
4. **观察者模式**：Observer模式定义了一种对象间的一对多依赖关系，当一个对象的状态发生变化时，所有依赖于它的对象都会收到通知并进行相应的更新。在iOS中，KVO（Key-Value Observing）和通知中心（NSNotificationCenter）就是基于观察者模式的实现。
5. **MVC（Model-View-Controller）模式**：用于将应用的数据、界面和逻辑进行分离，提高代码的可维护性和重用性。

![设计模式](/Users/xiaozhuzhu/Documents/work/iOS资料/image/设计模式.png)

### 6、设计模式六大原则：

1. 单一职责（Single responsibility principle）

2. 开闭原则（Open–closed principle）：软件实体（类、模块、函数等）应该对扩展开放，对修改关闭。即通过扩展来实现新功能，而不是直接修改已有代码。

3. 里氏替换原则（Liskov substitution principle）：子类对象可以替换其父类对象，而程序仍能正常运行。即子类应该能够完全替代父类并符合使用父类的所有约定。示例：考虑一个场景，有一个接收图形对象并进行绘制的函数。根据里氏替换原则，子类对象（例如`Circle`、`Rectangle`）可以替换父类对象（`Shape`）作为函数参数。

   ```objective-c
   - (void)drawShape:(Shape *)shape;
   ```

   

4. 接口隔离原则（Interface Segregation Principle，ISP）：客户端不应该被强迫依赖于它们不使用的接口。应该将庞大的接口拆分为更小、更具体的接口，以避免客户端实现不必要的方法。示例：考虑一个名为`Printer`的打印机类，它有打印、扫描、复印等功能。根据接口隔离原则，我们应该将庞大的接口拆分为更小的接口，例如`PrintProtocol`和`ScanProtocol`，以便客户端只依赖于它们需要的接口。

   ```objective-c
   @protocol PrintProtocol <NSObject>
   
   - (void)print;
   
   @end
   
   @protocol ScanProtocol <NSObject>
   
   - (void)scan;
   
   @end
   
   @interface Printer : NSObject <PrintProtocol, ScanProtocol>
   
   @end
   
   ```

   

5. 依赖倒置原则（Dependency inversion principle）：高层模块不应该依赖于低层模块，两者都应该依赖于抽象。抽象不应该依赖于具体实现细节，具体实现细节应该依赖于抽象。示例：假设有一个名为`Logger`的日志记录器类，它负责记录日志。根据依赖倒置原则，高层模块（例如业务逻辑类）应该依赖于抽象（例如定义一个`LoggerProtocol`协议），而不是具体的日志记录器类。

   ```objective-c
   @protocol LoggerProtocol <NSObject>
   
   - (void)logMessage:(NSString *)message;
   
   @end
   
   @interface Logger : NSObject <LoggerProtocol>
   
   @end
   
   @interface BusinessLogic : NSObject
   
   @property (nonatomic, strong) id<LoggerProtocol> logger;
   
   @end
   
   ```

   

6. 迪米特法则：一个软件实体应该尽可能少的直接与其他软件实体交互，最好引入第三者来进行交互。例如：MVVM中，view和model互不知道对方存在，通过viewmodel进行交互。

**iOS一般用到前五个（简称SOLID）**

## 十二、网络

### **1、IP：网络层 ；  TCP：传输层 ；  http：应用层**

### **2、http 和 https 的区别**

- http是明文传输，https是密文传输，所以https相对安全。
- Https需要申请证书，http不需要
- http比https响应快，因为它没有加密的过程。
- https和http使用的端口不一样，https默认是443，http默认是80

HTTPS 比 HTTP 多了一个安全性层，该安全性层是通过使用 **SSL**（Secure Socket Layer）或 **TLS**（Transport Layer Security）协议来实现的。这个安全性层在传输过程中对数据进行加密和认证，从而提供了以下几个方面的保护：
* 数据加密： 在 HTTPS 中，通过使用加密算法对传输的数据进行加密，使得数据在传输过程中难以被窃取或篡改。这意味着即使被抓包获取到数据，也很难解密其内容。
* 身份认证： HTTPS 使用证书来验证服务器的身份，确保客户端与服务器之间建立的连接是可信的。客户端可以验证服务器的证书，并确保其与正确的服务器进行通信，防止中间人攻击。
* 完整性保护： 在 HTTPS 中，通过使用加密算法和消息认证码（MAC）来保护数据的完整性。这样可以检测出数据在传输过程中是否被篡改或损坏。
总结来说，HTTPS 相对于 HTTP 来说，提供了数据加密、身份认证和完整性保护等安全机制，从而更安全地传输数据，并防止数据被窃取、篡改或劫持。这使得 HTTPS 成为保护敏感信息和进行安全通信的首选协议。

TLS（Transport Layer Security）和 SSL（Secure Sockets Layer）协议都是用于网络通信安全的协议，用于在客户端和服务器之间建立安全的通信连接。它们的作用是加密通信数据、验证通信双方身份以及保证数据的完整性。

SSL 是最早的安全通信协议，而 TLS 是其后继者。TLS 的设计目标是解决 SSL 的安全漏洞和弱点，并提供更强大的安全性。

TLS 和 SSL 协议的工作流程如下：
* 握手阶段（Handshake）： 在握手阶段，客户端和服务器之间进行协商，建立安全通信的参数和密钥。这个过程包括以下步骤：
    * 客户端向服务器发送加密套件列表、支持的协议版本等信息。
    * 服务器从客户端提供的加密套件列表中选择一个加密算法和密钥交换算法。
    * 服务器返回包含证书、公钥等信息的握手响应。
    * 客户端验证服务器的证书，获取公钥并生成会话密钥。
* 加密通信阶段（Secure Communication）： 在握手阶段完成后，客户端和服务器之间建立了安全的通信连接。在这个阶段，数据通过密钥交换算法进行加密和解密，确保数据在传输过程中的保密性和完整性。
TLS 和 SSL 的主要区别在于以下几个方面：
* 版本差异： SSL 有多个版本，如 SSL 2.0、SSL 3.0，而 TLS 有多个版本，如 TLS 1.0、TLS 1.1、TLS 1.2、TLS 1.3。
* 安全性： TLS 修复了 SSL 存在的一些安全漏洞和弱点，并提供了更强大的安全性。
* 加密算法： TLS 通常支持更强大的加密算法和密钥交换算法，如 AES、RSA、Diffie-Hellman 等。
* 握手过程： TLS 的握手过程相对于 SSL 有一些差异，TLS 使用更严格的验证和协商流程。
尽管 TLS 是 SSL 的继任者，但人们通常将两者合称为 TLS/SSL 协议，并广泛应用于保护网络通信的安全性。

### **3、TCP、UDP的区别**

- tcp面向连接，传输数据必须是在持续连接的基础上；有三次握手；比较慢，但是可靠。

- Udp不面向连接，传输数据前是不与对方建立连接的，对接收到的数据也不发送确认通知；效率高，但是不确定是否发送成功。


#### **三次握手**

1、客户端向服务端发送一个请求报文（SYN），报文中包含自己的初始序列号（client_isn），进入SYN_SEND状态
2、服务端收到客户端的请求报文后，会向客户端发送一个确认报文（SYN+ACK），报文中包含自己的初始序列号（服务端随机生成server_isn）和确认应答号（client_isn + 1），并进入SYN_RECIEVED状态
3、客户端收到服务端的报文后，会再向服务端发送一个确认报文，其中包含确认应答号（server_isn + 1），并进入established状态；服务端收到应答后，也进入了ESTABLISHED状态（已连接状态）

P.S. 第三次握手是可以携带传输数据的，前两次握手不能携带传输数据。

为什么要三次握手而不是两次？
**三次握手是为了防止已失效的连接请求报文突然又传送到服务器，从而导致错误和资源浪费。**

1. **核心问题：网络环境的不可靠性**

想象一下，你正在通过一个非常糟糕、延迟很高的电话网络打电话。你说的话可能会重复、延迟，甚至乱序到达。

TCP 的三次握手就是为了在这样一个不可靠的网络基础上，建立一个**可靠**的连接。它需要解决三个核心问题：

1. **确认双方的发送和接收能力都正常**。
2. **同步序列号**：为后续的可靠传输做准备（序列号用于保证数据包顺序、去重和确认）。
3. **避免历史连接造成的混乱**：这是“两次握手”无法解决的关键问题。

------

2. **两次握手会带来什么问题？（历史连接问题）**

假设我们只用两次握手：

1. **客户端** 发送一个连接请求报文（SYN包）给服务器。这个包里包含客户端的初始序列号 `seq = x`。
2. **服务器** 收到请求后，必须分配内存等资源来维护这个即将建立的连接。然后回复一个确认报文（SYN-ACK包），其中包含服务器的初始序列号 `seq = y` 和对客户端序列号的确认 `ack = x + 1`。
3. **连接建立！** 双方开始传输数据。

**现在，问题来了：**

如果那个客户端的 SYN 请求报文因为网络拥堵**延迟**了。客户端迟迟收不到服务器的回应，于是**超时重传**了一个新的 SYN 请求，并成功建立了连接、传输完数据、关闭了连接。

**此时，那个迷路的、旧的 SYN 请求报文**终于历经千辛万苦到达了服务器。

服务器无法区分这是一个旧的无效报文还是一个新的有效请求。按照两次握手的规则，它会：

1. 认为这是一个新的连接请求。
2. 立刻分配资源。
3. 回复一个 SYN-ACK 报文给客户端。

如果是两次握手，到这里连接就已经建立了。但客户端知道这个回应是针对那个早已失效的旧请求的，它根本不想建立这个连接，于是它会**忽略**服务器的这个 SYN-ACK 报文。

但服务器却傻傻地以为连接已经建立，会一直占用着为这个连接分配的内存和资源，**空等客户端发送数据**。这会导致服务器的资源被白白浪费。如果这种情况发生多次，服务器可能就有大量无效连接，造成**资源耗尽和性能下降**。这就是所谓的“SYN Flood”攻击的一种利用方式。

------

3. **三次握手如何解决这个问题？**

让我们在三次握手的规则下重演上面的场景：

1. 旧的 SYN 延迟报文到达服务器，服务器依旧会分配资源并回复 SYN-ACK。
2. 客户端收到这个 SYN-ACK。由于这是一个对旧请求的回应，客户端知道自己没有发起新的连接，因此它不会发送最后的 ACK 确认，而是会回复一个 **RST（复位）报文** 告诉服务器“这是个错误，请重置连接”。
3. 服务器收到 RST 报文后，就会释放之前分配的资源，避免了资源的浪费。

**第三次握手（客户端的 ACK）是一个关键的“确认之确认”**。只有在服务器收到了这个 ACK 之后，它才能百分之百地确定：“客户端确实收到了我的回应，并且真心想要建立这个连接”。这时服务器才会真正进入连接已建立的状态。

#### **四次挥手：**

1、客户端向服务端发送一个连接释放报文（FIN），请求关闭连接
2、服务端收到请求后，向客户端回应一个确认报文（ACK），表示已收到请求
3、服务端在完成未完成的数据传输后，会向客户端发送连接释放报文（FIN）
4、客户端在收到服务端发送的连接释放报文后，会回复一个确认报文（ACK），表示接受关闭请求，并进入TIME_WAIT状态，一段时间后，连接关闭。

**可以把四次挥手理解为两个二次挥手：**

- 第一次 + 第二次挥手：关闭了从客户端到服务器的通道。
- 第三次 + 第四次挥手：关闭了从服务器到客户端的通道。

### 4、socket

套接字；socket是对TCP/IP协议的封装，Socket本身并不是协议，而是一个调用接口(API)。它能让我们更方便地使用TCP/IP协议栈而已，是对TCP/IP协议的抽象，从而形成了我们知道的一些最基本的函数接口，比如create、listen、connect、accept、send、read和write等等。



### 5、XMPP

应用层协议，底层也是建立socket通信，其基本的网络形势是客户端通过tcp/ip连接服务端，然后进行xml格式的信息收发。



## 十三、安全措施

**1、网络**

1. 使用https请求
2. 登录账号密码
3. 后台返回的数据进行加密（对称加密：DES。非对称加密：RSA）

**2、日志**

1. release环境下不打印日志

**3、数据存储**

1. 把秘钥A加密后再定义成宏定义B，其中对秘钥加密的秘钥C
2. 把保存在钥匙串里的数据进行加密再保存
3. plist文件里的内容如果是重要的则进行加密以后再存储（因为plist可以通过ipa包获取到）

**4、APP加固**

1. 代码混淆：就是把易读的类名、方法名替换成不易读的名字。常用的方法有宏替换和脚本替换。
2. 核心代码用c语音



## 十四、UI（更新中）

### **1、CAlayer和UIView的区别和联系**

1. **核心职责不同**

- **UIView**：是 iOS 界面的基础组件，主要负责**用户交互管理**和**视图层级控制**。它继承自`UIResponder`，能响应触摸、手势等用户事件，同时管理子视图的布局和生命周期。
- **CALayer**：属于 Core Animation 框架，主要负责**内容渲染**和**视觉呈现**。它专注于绘制内容（如颜色、图片、形状等）、设置视觉属性（如阴影、圆角、边框），以及处理动画效果。

2. **继承关系与事件处理**

- **UIView**：继承自`UIResponder`，因此具备事件响应能力（如`touchesBegan:withEvent:`等方法），可以处理用户交互。
- **CALayer**：继承自`NSObject`，不具备事件响应能力，无法直接处理触摸等用户事件（但可以通过`hitTest:`等方法间接辅助判断点击区域）。

3. **层级结构关联**

- 每个`UIView`内部都包含一个根`CALayer`（通过`view.layer`属性访问），视图的视觉内容实际由这个根图层绘制。
- 当添加子视图（`addSubview:`）时，UIView 会自动为子视图的根图层添加到自身根图层的子图层中（即`layer.addSublayer(subview.layer)`）。因此，**视图层级与图层层级是一一对应的**，但管理方式不同（视图用`UIView`的方法，图层用`CALayer`的方法）。

4. **动画与渲染**

- **渲染**：所有视觉内容最终都通过`CALayer`渲染到屏幕上，`UIView`本身不负责绘制，其`draw(_ rect: CGRect)`方法本质是为关联的`layer`提供绘制内容。
- **动画**：Core Animation 的动画效果本质是作用于`CALayer`的属性（如`position`、`opacity`），`UIView`的动画方法（如`UIView.animate(withDuration:)`）本质是对`CALayer`动画的封装。

5. **性能与使用场景**

- 若仅需展示静态内容且无需交互（如复杂图形、渐变背景），直接使用`CALayer`会更轻量（减少`UIResponder`相关的内存开销）。
- 若需要处理用户交互（如按钮、输入框），则必须使用`UIView`。

**总结**

简单来说，`UIView`是 “管理者”，负责交互和视图层级；`CALayer`是 “绘制者”，负责视觉呈现和动画。二者分工协作，共同构成 iOS 的界面系统。这种职责分离的设计，既保证了交互逻辑的清晰，也优化了渲染性能。

## 十五、JS 交互实战

**jssdk创建一个字典来管理api方法名和执行函数的映射关系，注册api方法时，将方法名作为key，block函数作为value。**

1. js 调用 iOS 时，webview 收到 decidePolicyForNavigationAction 代理回调，在回调中，iOS 会再调用 js 的一个统一的方法，该方法会返回 js 的一些调用信息，比如方法名、参数，ios 根据方法名在本地维护的映射字典中找到 block 函数，
找到就执行。

2. 如果 js 需要返回值，js 那边会定义一个回调函数（比如 _handleMessageFromObjC），当 js 调用 iOS 时，会给 iOS 传入一个callbackId，iOS 执行完函数时，会再调用 js 定义好的回调函数（iOS 调用 js 使用 - (void)evaluateJavaScript:(NSString *)javaScriptString completionHandler:(WK_SWIFT_UI_ACTOR void (^ _Nullable)(_Nullable id, NSError * _Nullable error)，javaScriptString 中拼接方法名和数据，如果是媒体数据，则是 base64 数据) completionHandler 函数），并将返回值和 callbackId 一并返回，js 根据 callbackId 来确定自己需要的返回数据。


问题：
为什么不直接使用 addScriptMessageHandler:,通过handle回调来让 js 调用 iOS 的方法？
各端处理逻辑统一，而且可移植性比较强，如果以后要做自己的 webview，可以很方便的切换
js 端逻辑也比较清晰，调用方法和传递参数结构上更清晰
项目比较早一开始应该使用的是 UIWebview，webview 应该没有这个方法

注意：
1. 第1条中，并不是所有的js调用iOS都会收到 decidePolicyForNavigationAction 回调，比如通过 MessageHandler 调用 iOS 不会
// JS 端 - 不会触发 decidePolicyForNavigationAction
window.webkit.messageHandlers.nativeHandler.postMessage({
    method: 'showAlert',
    message: 'Hello iOS'
});

这个交互的完整流程是
// iOS 设置
- (void)setupMessageHandler {
    [self.webView.configuration.userContentController 
     addScriptMessageHandler:self name:@"nativeHandler"]; // 注册一个方法名，供 js 调用
    }

// js 调用后 iOS 会收到 didReceiveScriptMessage 回调
- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message {
    NSDictionary *body = message.body;
    NSString *method = body[@"method"];
  
    if ([method isEqualToString:@"showAlert"]) {
        NSString *msg = body[@"message"];
        [self showAlert:msg];
    }
  }

2. js 通过 URL Scheme - 会触发
// JS 端 - 会触发 decidePolicyForNavigationAction
window.location.href = 'myapp://showAlert?message=hello';

// 或者
document.location = 'tel:10086';

// 或者创建链接点击
var a = document.createElement('a');
a.href = 'myapp://action';
a.click();

// iOS 端 - 会被调用
- (void)webView:(WKWebView *)webView 
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction 
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
  
    NSString *urlString = navigationAction.request.URL.absoluteString;
  
    if ([urlString hasPrefix:@"myapp://"]) {
        // 处理自定义协议
        [self handleCustomScheme:navigationAction.request.URL];
        decisionHandler(WKNavigationActionPolicyCancel); // 阻止导航
        return;
    }
  
    decisionHandler(WKNavigationActionPolicyAllow);
}


----------------------------------------- 概念理解 ----------------------------------------- 
- (void)addUserScript:(WKUserScript *)userScript
作用
在页面加载时自动注入JavaScript代码，这些代码会成为页面的一部分。
特点
主动注入：iOS主动向WebView注入JS代码
自动执行：页面加载时自动执行，不需要iOS再次调用
一次性设置：设置后对所有页面生效
扩展页面功能：为页面添加新的JS函数、变量或修改页面行为
使用场景：• 为页面添加工具函数<br>• 修改页面样式/行为<br>• 建立通信桥梁<br>• 页面功能增强

- (void)addScriptMessageHandler:(id<WKScriptMessageHandler>)scriptMessageHandler 
                           name:(NSString *)name;
                           作用
                       注册一个消息处理器，让JavaScript可以向iOS发送消息。
                       特点
                       被动接收：iOS等待JS发送消息
                       双向通信桥梁：建立JS到iOS的通信通道
                       事件驱动：当JS调用时才触发
                       数据传递：可以传递复杂的数据结构



## 十六、**动态库和静态库的区别**

在 iOS 开发中，静态库（Static Library）和动态库（Dynamic Library）是代码复用的两种核心形式，其本质区别体现在**链接时机、存在形式、复用方式**以及**对 App 构建和运行的影响**上。以下是更贴合实际开发场景的详细对比：

### 1、核心定义与本质差异

- **静态库**：**编译期**被完整复制到目标程序（App 可执行文件）中的二进制文件，最终成为 App 可执行文件的一部分。
  常见形式：`.a` 文件（纯二进制）、静态 `.framework`（包含二进制和头文件）。
- **动态库**：**运行时**由系统动态加载到内存的独立二进制文件，**不会被复制到 App 可执行文件中**，仅在 App 运行时通过引用关系被调用。
  常见形式：`.dylib` 文件、动态 `.framework`（系统框架如 `UIKit` 或应用私有动态库）。

### 2、关键区别对比

| **对比维度**              | **静态库**                                 | **动态库**                                                   |
| ------------------------- | ------------------------------------------ | ------------------------------------------------------------ |
| **链接时机**              | 编译期（Build 阶段）                       | 编译期记录引用，运行时（App 启动 / 使用时）实际加载          |
| **存在形式**              | 合并到 App 可执行文件（`Mach-O`）中        | 独立文件，存放在 App 沙盒 `Frameworks` 目录（私有库）或系统目录（系统库） |
| **包体积影响**            | 直接增加 App 可执行文件体积（完整复制）    | 不增加可执行文件体积，但以独立文件形式占用 `.ipa` 体积       |
| **跨 App 复用能力**       | 无（每个 App 都包含独立副本）              | 仅系统动态库可被多 App 共享（如 `UIKit`）；应用私有动态库不可跨 App 共享（受沙盒和签名限制） |
| **内存共享（单 App 内）** | 不可共享（多模块引用时重复存储）           | 可共享（一份内存被 App 内多模块复用）                        |
| **更新方式**              | 需重新编译 App 并提交更新                  | 系统库随系统更新；应用私有动态库需随 App 一起更新            |
| **编译速度**              | 修改后依赖它的模块需重新编译，大型项目较慢 | 独立编译，修改后仅需重新链接，编译速度更快                   |
| **启动性能**              | 无运行时加载开销（编译期已链接完成）       | 启动时需动态链接器（`dyld`）加载，有轻微启动开销             |
| **依赖管理**              | 编译期合并，无运行时依赖问题               | 运行时依赖动态库存在性，缺失会导致崩溃（`dyld: Library not loaded`） |
| **工程配置**              | 仅需 “Link Binary With Libraries”（链接）  | 应用私有库需同时勾选 “Link Binary With Libraries” 和 “Embed & Sign”（嵌入并签名） |

### 3、适用场景差异

**静态库适合：**

1. **稳定少变的基础模块**（如加密算法、工具类）：避免动态库的运行时加载开销，提升启动速度。
2. **体积较小的通用逻辑**（如日志工具）：过小的模块独立为动态库会因元数据开销 “得不偿失”。
3. **第三方闭源 SDK**（如统计、支付 SDK）：通过静态库分发可避免签名和依赖问题，兼容性更好。
4. **对启动速度敏感的核心模块**（如 App 初始化逻辑）：无运行时链接开销，减少启动耗时。

**动态库适合：**

1. **频繁变动的业务模块**（如首页、商城）：独立编译可大幅提升开发和打包效率（尤其团队协作时）。
2. **体积较大的独立模块**（如视频播放、地图）：避免静态库导致的可执行文件膨胀，降低启动压力。
3. **多 Target 共享的模块**（如同时被主 App 和 Extension 引用的网络层）：减少多 Target 重复打包的冗余体积。
4. **模块化架构的核心组件**：支持模块解耦，可实现启动后延迟加载（优化冷启动速度）。

### 4、总结

静态库和动态库的核心差异在于 **“是否在编译期合并到可执行文件”**：

- 静态库是 “编译期合并，随 App 一体分发”，优势是启动快、兼容性好，劣势是可执行文件膨胀、编译效率低；
- 动态库是 “运行时加载，独立文件存在”，优势是控制可执行文件大小、提升编译效率、支持单 App 内内存共享，劣势是有启动开销、应用私有库无法跨 App 共享。

实际开发中，大型 App 通常采用 “动态库 + 静态库” 混合架构：用动态库拆分业务模块，用静态库集成稳定基础组件，兼顾开发效率和运行性能。

## 十七、cocoapods 工作原理

### **1. CocoaPods 工作原理关键流程：**

1. 解析 Podfile，读取依赖声明及版本约束
2. 从 specs 仓库查找匹配的.podspec 描述文件，递归解析所有子依赖
3. 下载依赖库到本地，生成 Pods 目录及 Pods.xcodeproj
4. 创建 xcworkspace 关联主项目与 Pods 项目
5. 通过配置文件统一管理编译参数，将依赖以静态库或动态框架形式集成
6. 生成 Podfile.lock 锁定版本，确保环境一致性

**详细介绍：**

CocoaPods 是 iOS 开发中常用的依赖管理工具，其工作原理可以从以下几个核心环节来理解：

1. **依赖解析机制**

- 当执行 `pod install` 时，CocoaPods 会读取项目中的 `Podfile`，分析其中声明的依赖库及其版本约束
- 通过查询本地缓存的 specs 仓库（`.cocoapods/repos`），找到符合版本要求的依赖库描述文件（.podspec）
- 采用递归方式解析所有子依赖，构建完整的依赖关系树，解决版本冲突

2. **项目集成方式**

- 生成中间产物 `Pods` 目录，存放所有下载的依赖源码或二进制文件
- 创建并配置 `Pods.xcodeproj` 项目文件，将所有依赖库组织成独立的 target
- 生成 `xcworkspace` 文件，将主项目与 Pods 项目关联，形成统一的开发环境

3. **依赖管理流程**

- 首次安装时从远程仓库克隆 specs 索引（默认是 CocoaPods/Specs）
- 根据 .podspec 描述下载指定版本的依赖库到本地缓存
- 通过 Xcode 配置文件（如 .xcconfig）统一管理依赖库的编译参数、头文件路径等
- 采用静态链接或动态框架的方式，将依赖库与主项目代码合并编译

4. **版本控制策略**

- 生成 `Podfile.lock` 记录当前安装的所有依赖的确切版本，确保团队开发环境一致性
- 支持语义化版本号（Semantic Versioning）和多种版本约束语法（如 `~> 1.0`）
- 提供 `pod update` 命令用于更新依赖到符合约束的最新版本

通过这种机制，CocoaPods 有效解决了 iOS 开发中第三方库的集成、版本管理和依赖冲突等问题，显著提升了开发效率。

**Podfile.lock** :

是 CocoaPods 生成的版本锁定文件，其核心作用是**记录当前项目中所有依赖库的精确版本号**（包括直接依赖和间接依赖）。

具体来说：

- 首次执行 `pod install` 时，CocoaPods 会根据 `Podfile` 中的版本约束解析并安装合适的依赖版本，然后将这些**确切版本号**写入 `Podfile.lock`。
- 后续在同一项目中执行 `pod install` 时，CocoaPods 会优先读取 `Podfile.lock`，强制安装其中记录的版本，而非重新解析 `Podfile` 去获取最新版本。
- 团队协作或多环境开发时，将 `Podfile.lock` 纳入版本控制（如 Git），可确保所有开发者、CI 环境或打包机器上安装的依赖版本完全一致，避免因版本差异导致的兼容性问题。

若需更新依赖版本，需手动执行 `pod update`，此时会重新解析版本约束并更新 `Podfile.lock`。
