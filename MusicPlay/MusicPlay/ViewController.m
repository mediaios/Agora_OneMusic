//
//  ViewController.m
//  MusicPlay
//
//  Created by yedexiong on 16/11/3.
//  Copyright © 2016年 yoke121. All rights reserved.
//

#import "ViewController.h"
#import "MusicModel.h"
#import "UIImageView+WebCache.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AgoraRtcEngineKit/AgoraRtcEngineKit.h>
@interface ViewController ()<AgoraRtcEngineDelegate,AVAudioPlayerDelegate>
//音乐名
@property (weak, nonatomic) IBOutlet UILabel *musicName;
//演唱者
@property (weak, nonatomic) IBOutlet UILabel *artist;
//音乐图片
@property (weak, nonatomic) IBOutlet UIImageView *musicIcon;
//当前播放时间
@property (weak, nonatomic) IBOutlet UILabel *currentTime;
//音乐时常
@property (weak, nonatomic) IBOutlet UILabel *duration;

@property (weak, nonatomic) IBOutlet UIButton *playBtn;
//缓冲进度条
@property (weak, nonatomic) IBOutlet UIProgressView *loadTimeProgress;
//播放进度滑块
@property (weak, nonatomic) IBOutlet UISlider *playSlider;
//数据源
@property(nonatomic,strong) NSMutableArray *dataSource;
//播放器
@property(nonatomic,strong) AVPlayer *player;

//当前播放音乐的索引
@property(nonatomic,assign) NSInteger currentIndex;
//当前播放的音乐模型
@property(nonatomic,strong) MusicModel *currentModel;

//缓存音乐图片
@property(nonatomic,strong) NSMutableDictionary *musicImageDic;

//当前歌曲进度监听者
@property(nonatomic,strong) id timeObserver;

@property (nonatomic,strong) AgoraRtcEngineKit *agoraKit;

@end

@implementation ViewController

- (void)viewDidLoad {
   
    [super viewDidLoad];
   
    [self loadData];
    
    self.currentIndex = 0;
    [self playBtnAction:self.playBtn];
    
    self.agoraKit = [AgoraRtcEngineKit sharedEngineWithAppId:@"" delegate:self];
    [self.agoraKit setChannelProfile:AgoraChannelProfileLiveBroadcasting];
    [self.agoraKit setAudioProfile:AgoraAudioProfileMusicHighQualityStereo scenario:AgoraAudioScenarioGameStreaming];
    [self.agoraKit setClientRole:AgoraClientRoleAudience];
    NSLog(@"SDK ver: %@",[AgoraRtcEngineKit getSdkVersion]);
}

- (void)customAddNotification {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(audioRouteChangeListenerCallback:)
                                                 name:AVAudioSessionRouteChangeNotification object:nil];
    
//    [[NSNotificationCenter defaultCenter] addObserver:self
//                                             selector:@selector(otherAppAudioSessionCallBack:)
//                                                 name:AVAudioSessionSilenceSecondaryAudioHintNotification object:nil];
//
//    [[NSNotificationCenter defaultCenter] addObserver:self
//                                             selector:@selector(systermAudioSessionCallBack:)
//                                                 name:AVAudioSessionInterruptionNotification object:nil];
}

// 监听外部设备改变
- (void)audioRouteChangeListenerCallback:(NSNotification*)notification {
    NSDictionary *interuptionDict = notification.userInfo;
    NSInteger routeChangeReason = [[interuptionDict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    switch (routeChangeReason) {
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:{
            NSLog(@"headset input");
            break;
        }
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:{
            NSLog(@"pause play when headset output");
//            [self.avPlayer pause];
            break;
        }
        case AVAudioSessionRouteChangeReasonCategoryChange:
            NSLog(@"AVAudioSessionRouteChangeReasonCategoryChange");
            break;
    }
}


#pragma mark - private
-(void)loadData
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"music" ofType:@"json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSArray *datas =  [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    for (NSDictionary *dic in datas) {
        
        MusicModel *model = [[MusicModel alloc] initWithDic:dic];
        [self.dataSource addObject:model];
   
    }
}

-(void)reloadUI:(MusicModel*)model
{
    self.musicName.text = model.name;
    self.artist.text = model.artist;
    [self.musicIcon sd_setImageWithURL:[NSURL URLWithString:model.cover]];
    self.duration.text = model.duration;
    self.playBtn.selected = YES;
    self.playSlider.value = 0;
    self.loadTimeProgress.progress = 0;
    
}

#pragma mark- 音乐播放相关
//播放音乐
-(void)playWithUrl:(MusicModel*)model
{
    AVPlayerItem *item = [[AVPlayerItem alloc] initWithURL:[NSURL URLWithString:model.url]];
    
    //替换当前音乐资源
    [self.player replaceCurrentItemWithPlayerItem:item];
    
    //刷新界面UI
    [self reloadUI:model];
  
    //监听音乐播放完成通知
    [self addNSNotificationForPlayMusicFinish];
    
    //开始播放
    [self.player play];
    
    //监听播放器状态
    [self addPlayStatus];
    
    //监听音乐缓冲进度
    [self addPlayLoadTime];
    
    //监听音乐播放的进度
    [self addMusicProgressWithItem:item];
    
   //记录当前播放音乐的索引
    self.currentIndex = [model.Id integerValue];
    self.currentModel = model;
    
    //音乐锁屏信息展示
    [self setupLockScreenInfo];
    
}


#pragma mark - 设置锁屏信息

//音乐锁屏信息展示
- (void)setupLockScreenInfo
{
    // 1.获取锁屏中心
    MPNowPlayingInfoCenter *playingInfoCenter = [MPNowPlayingInfoCenter defaultCenter];
    
   //初始化一个存放音乐信息的字典
    NSMutableDictionary *playingInfoDict = [NSMutableDictionary dictionary];
    // 2、设置歌曲名
    if (self.currentModel.name) {
        [playingInfoDict setObject:self.currentModel.name forKey:MPMediaItemPropertyAlbumTitle];
    }
    // 设置歌手名
    if (self.currentModel.artist) {
        [playingInfoDict setObject:self.currentModel.artist forKey:MPMediaItemPropertyArtist];
    }
    // 3设置封面的图片
    UIImage *image = [self getMusicImageWithMusicId:self.currentModel];
    if (image) {
        MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithImage:image];
        [playingInfoDict setObject:artwork forKey:MPMediaItemPropertyArtwork];
    }
    
    // 4设置歌曲的总时长
    [playingInfoDict setObject:self.currentModel.detailDuration forKey:MPMediaItemPropertyPlaybackDuration];
    
    //音乐信息赋值给获取锁屏中心的nowPlayingInfo属性
    playingInfoCenter.nowPlayingInfo = playingInfoDict;
    
    // 5.开启远程交互
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
}

//获取远程网络图片，如有缓存取缓存，没有缓存，远程加载并缓存
-(UIImage*)getMusicImageWithMusicId:(MusicModel*)model
{
    UIImage *image;
    NSString *key = [model.Id stringValue];
    UIImage *cacheImage = self.musicImageDic[key];
    if (cacheImage) {
        image = cacheImage;
    }else{
        //这里用了非常规的做法，仅用于demo快速测试，实际开发不推荐，会堵塞主线程
        //建议加载歌曲时先把网络图片请求下来再设置
        NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:model.cover]];
        image =  [UIImage imageWithData:data];
        if (image) {
            [self.musicImageDic setObject:image forKey:key];
            
        }
    }
    
    return image;
}


//监听远程交互方法
- (void)remoteControlReceivedWithEvent:(UIEvent *)event
{
    
    switch (event.subtype) {
        //播放
        case UIEventSubtypeRemoteControlPlay:{
            [self.player play];
                    }
            break;
        //停止
        case UIEventSubtypeRemoteControlPause:{
            [self.player pause];
                   }
            break;
        //下一首
        case UIEventSubtypeRemoteControlNextTrack:
            [self nextBtnAction:nil];
            break;
        //上一首
        case UIEventSubtypeRemoteControlPreviousTrack:
            [self lastBtnAction:nil];
            break;
            
        default:
            break;
    }
}

#pragma mark - NSNotification
-(void)addNSNotificationForPlayMusicFinish
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    //给AVPlayerItem添加播放完成通知
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playFinished:) name:AVPlayerItemDidPlayToEndTimeNotification object:_player.currentItem];
}

-(void)playFinished:(NSNotification*)notification
{
    //播放下一首
    [self nextBtnAction:nil];
}



#pragma mark - 监听音乐各种状态
//通过KVO监听播放器状态
-(void)addPlayStatus
{
    
    [self.player.currentItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
        
}
//移除监听播放器状态
-(void)removePlayStatus
{
    if (self.currentModel == nil) {return;}
    
    [self.player.currentItem removeObserver:self forKeyPath:@"status"];
}



//KVO监听音乐缓冲状态
-(void)addPlayLoadTime
{
  [self.player.currentItem addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionNew context:nil];
    
}
//移除监听音乐缓冲状态
-(void)removePlayLoadTime
{
    if (self.currentModel == nil) {return;}
    [self.player.currentItem removeObserver:self forKeyPath:@"loadedTimeRanges"];
}

//监听音乐播放的进度
-(void)addMusicProgressWithItem:(AVPlayerItem *)item
{
    //移除监听音乐播放进度
    [self removeTimeObserver];
    __weak typeof(self) weakSelf = self;
    self.timeObserver =  [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1.0, 1.0) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        //当前播放的时间
        float current = CMTimeGetSeconds(time);
        //总时间
        float total = CMTimeGetSeconds(item.duration);
        if (current) {
            float progress = current / total;
            //更新播放进度条
           weakSelf.playSlider.value = progress;
            weakSelf.currentTime.text = [weakSelf timeFormatted:current];
        }
    }];
    
}

//转换成时分秒
- (NSString *)timeFormatted:(int)totalSeconds
{
    int seconds = totalSeconds % 60;
    int minutes = (totalSeconds / 60) % 60;
    
    return [NSString stringWithFormat:@"%02d:%02d",minutes, seconds];
}
//移除监听音乐播放进度
-(void)removeTimeObserver
{
    if (self.timeObserver) {
        [self.player removeTimeObserver:self.timeObserver];
        self.timeObserver = nil;
    }
}

//观察者回调
-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    if ([keyPath isEqualToString:@"status"]) {
        switch (self.player.status) {
            case AVPlayerStatusUnknown:
            {
                NSLog(@"未知转态");
            }
                break;
            case AVPlayerStatusReadyToPlay:
            {
                NSLog(@"准备播放");
            }
                break;
            case AVPlayerStatusFailed:
            {
                NSLog(@"加载失败");
            }
                break;
                
            default:
                break;
        }
        
    }
    
    if ([keyPath isEqualToString:@"loadedTimeRanges"]) {
        
        NSArray * timeRanges = self.player.currentItem.loadedTimeRanges;
        //本次缓冲的时间范围
        CMTimeRange timeRange = [timeRanges.firstObject CMTimeRangeValue];
        //缓冲总长度
        NSTimeInterval totalLoadTime = CMTimeGetSeconds(timeRange.start) + CMTimeGetSeconds(timeRange.duration);
        //音乐的总时间
        NSTimeInterval duration = CMTimeGetSeconds(self.player.currentItem.duration);
        //计算缓冲百分比例
        NSTimeInterval scale = totalLoadTime/duration;
        //更新缓冲进度条
       self.loadTimeProgress.progress = scale;
    }
}


#pragma mark - action
//播放上一首
- (IBAction)lastBtnAction:(UIButton *)sender
{
    //取出下一首音乐模型
    if (self.currentIndex - 1 < 0) {
        self.currentIndex = self.dataSource.count -1;
    }else{
        self.currentIndex -= 1;
    }
    [self removePlayStatus];
    [self removePlayLoadTime];
    MusicModel *model = self.dataSource[self.currentIndex];
    [self playWithUrl:model];

}

//播放
- (IBAction)playBtnAction:(UIButton *)sender
{
    if (!sender.selected) {
        [self playWithUrl:self.dataSource[self.currentIndex]];
        sender.selected = YES;
    }else{
        [self.player pause];
        [self removePlayStatus];
        [self removePlayLoadTime];
        self.currentModel = nil;
        sender.selected = NO;
    }
    
}
//下一首
- (IBAction)nextBtnAction:(UIButton *)sender {
    //取出下一首音乐模型
    if (self.currentIndex +1 > self.dataSource.count -1) {
        self.currentIndex = 0;
    }else{
        self.currentIndex += 1;
    }
    [self removePlayStatus];
    [self removePlayLoadTime];
    MusicModel *model = self.dataSource[self.currentIndex];
     [self playWithUrl:model];

}
//移动滑块调整播放进度
- (IBAction)playSliderValueChange:(UISlider *)sender
{
    //根据值计算时间
    float time = sender.value * CMTimeGetSeconds(self.player.currentItem.duration);
    //跳转到当前指定时间
    [self.player seekToTime:CMTimeMake(time, 1)];
}


#pragma mark - getter
-(NSMutableArray *)dataSource
{
    if (_dataSource == nil) {
        _dataSource = [NSMutableArray array];
    }
    return _dataSource;
}
-(AVPlayer *)player
{
    if (_player == nil) {
        //初始化_player
        AVPlayerItem *item = [[AVPlayerItem alloc] initWithURL:[NSURL URLWithString:@""]];
        _player = [[AVPlayer alloc] initWithPlayerItem:item];
    }
    
    return _player;
}


-(NSMutableDictionary *)musicImageDic
{
    if (_musicImageDic == nil) {
        _musicImageDic = [NSMutableDictionary dictionary];
    }
    return _musicImageDic;
}


- (IBAction)onpressedBtnJoinChannel:(id)sender {
    // 此处需要判断音乐是否正在播放，如果正在播放，则记录一个flag
//    [self.agoraKit setAudioSessionOperationRestriction:AgoraAudioSessionOperationRestrictionAll];
    
     
//    AVAudioSession *session = [AVAudioSession sharedInstance];
//    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent];
//    //设置类型是播放。
//    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
//    //激活音频会话。
//    [session setActive:YES error:nil];
    
    int joinRes = [self.agoraKit joinChannelByToken:nil channelId:@"22222" info:nil uid:0 joinSuccess:nil];
    NSLog(@"join channel res: %d",joinRes);
}

- (IBAction)onPressedBtLeaveChannel:(id)sender {
//    [self.agoraKit leaveChannel:nil];
//
////    [application setStatusBarStyle:UIStatusBarStyleLightContent];
    //获取音频会话11
//    AVAudioSession *session = [AVAudioSession sharedInstance];
//    //设置类型是播放。
//    [session setCategory:AVAudioSessionCategoryPlayback error:nil];
//    //激活音频会话。
//    [session setActive:YES error:nil];
//    [self.player play];
    
//
//    // 此处根据flag决定是推到后台后仍然要继续播放，还是需要在控制中心点击按钮之后再播放。
    
//    [self myAudioMix];
    
    [self testMix];
    
    
}

- (void)testMix {
//    NSString *filePath = @"https://m801.music.126.net/20200617194835/fbb7a234728ac0d2dca553f57adab2fe/jdyyaac/0759/5359/0e5e/03e3409837d3435d8d4394c46862b9be.m4a";
    
    NSString *filePath = @"http://huandong.cn-bj.ufileos.com/578a_1843_21b9_a828f4186a7a5eaee3e6284bdb24e5f5.flac";
    
//    NSString *filePath = @"https://jqsj-oss.oss-cn-hangzhou.aliyuncs.com/md2/bgm/2020-05-27/1590557656968.mp3";
    BOOL loopback = YES;
    BOOL replace = NO;
    NSInteger cycle = 1;
    [self.agoraKit stopAudioMixing];
    [self.agoraKit adjustAudioMixingPlayoutVolume:5];
    int res =  [self.agoraKit startAudioMixing:filePath loopback:loopback replace:replace cycle:cycle];
    NSLog(@"QiDebug, mix res: %d",res);
}

//- (void)myAudioMix
//{
//        NSString *filePath = @"https://m801.music.126.net/20200617194835/fbb7a234728ac0d2dca553f57adab2fe/jdyyaac/0759/5359/0e5e/03e3409837d3435d8d4394c46862b9be.m4a";
////        NSString *filePath = @"https://jqsj-oss.oss-cn-hangzhou.aliyuncs.com/md2/bgm/2020-05-27/1590557656968.mp3";
//        BOOL loopback = YES;
//        BOOL replace = NO;
//        NSInteger cycle = 1;
//        [self.agoraKit stopAudioMixing];
//        [self.agoraKit adjustAudioMixingPlayoutVolume:5];
//        int res =  [self.agoraKit startAudioMixing:filePath loopback:loopback replace:replace cycle:cycle];
//        NSLog(@"QiDebug, mix res: %d",res);
//}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    NSLog(@"%s",__func__);
}

/* if an error occurs while decoding it will be reported to the delegate. */
- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError * __nullable)error
{
    NSLog(@"%s",__func__);
}

- (IBAction)onpressedBtnChangeAudioControl:(id)sender {
    [self.agoraKit setAudioSessionOperationRestriction:AgoraAudioSessionOperationRestrictionAll];
      [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord mode:AVAudioSessionModeDefault options:(AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionAllowBluetoothA2DP) error:nil];
}

static UInt64 beginTime;
- (IBAction)onpressedBtnBroadcast:(id)sender {
    beginTime = [[NSDate date] timeIntervalSince1970]*1000;


    UInt64 endTime1 = [[NSDate date] timeIntervalSince1970]*1000;
    NSLog(@"QiDebug, cha1: %llu",(endTime1 - beginTime));
    endTime1 = 0;
    
//    UInt64 beginTime_role = [[NSDate date] timeIntervalSince1970]*1000;
    [self.agoraKit setClientRole:AgoraClientRoleBroadcaster];
//    UInt64 endTime_role = [[NSDate date] timeIntervalSince1970]*1000;
//    NSLog(@"QiDebug, role cha1: %llu",(endTime_role - beginTime_role));
}

- (IBAction)onpressedBtnLeaveChannel:(id)sender {
    [self.agoraKit setClientRole:AgoraClientRoleAudience];
//    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:(AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionAllowBluetoothA2DP) error:nil];
}


- (IBAction)sdkControlAudioCategory:(id)sender {
    [self.agoraKit setAudioSessionOperationRestriction:AgoraAudioSessionOperationRestrictionNone];
}

- (void)rtcEngine:(AgoraRtcEngineKit *_Nonnull)engine localAudioMixingStateDidChanged:(AgoraAudioMixingStateCode)state errorCode:(AgoraAudioMixingErrorCode)errorCode
{
    NSLog(@"%s, state:%d , errorCode:%d",__func__,(int)state,(int)errorCode);
}

- (void)rtcEngine:(AgoraRtcEngineKit *_Nonnull)engine didJoinChannel:(NSString *_Nonnull)channel withUid:(NSUInteger)uid elapsed:(NSInteger)elapsed
{
    NSLog(@"%s,uid:%lu",__func__,uid);
}

- (void)rtcEngine:(AgoraRtcEngineKit *)engine firstLocalAudioFrame:(NSInteger)elapsed
{
    
    UInt64 endTime = [[NSDate date] timeIntervalSince1970]*1000;
    NSLog(@"QiDebug, cha: %llu",(endTime - beginTime));
    beginTime = 0;
    endTime = 0;
}


@end
