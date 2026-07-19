// DeltaruneVerification.m
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// 存储
#define kSteamIDKey @"com.deltarune.verifiedSteamID"

// 失败界面
@interface FailureViewController : UIViewController
@property (nonatomic, copy) void(^onRetry)(void);
@end

@implementation FailureViewController {
    UILabel *_label;
    NSInteger _countdown;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    // 从沙盒根目录读取图片
    NSString *imgPath = [NSHomeDirectory() stringByAppendingPathComponent:@"verification_failed.png"];
    UIImage *img = [UIImage imageWithContentsOfFile:imgPath];
    UIImageView *imgView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    imgView.contentMode = UIViewContentModeScaleAspectFit;
    imgView.image = img;
    [self.view addSubview:imgView];

    _label = [[UILabel alloc] initWithFrame:CGRectMake(0, 50, self.view.bounds.size.width, 30)];
    _label.textColor = [UIColor redColor];
    _label.textAlignment = NSTextAlignmentCenter;
    _label.font = [UIFont boldSystemFontOfSize:24];
    [self.view addSubview:_label];

    _countdown = 10;
    [self tick];
}
- (void)tick {
    _label.text = [NSString stringWithFormat:@"验证失败，%ld秒后重试", (long)_countdown];
    if (_countdown <= 0) { if (self.onRetry) self.onRetry(); return; }
    _countdown--;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self tick]; });
}
@end

// Web界面登录Steam
@interface SteamLoginVC : UIViewController <WKNavigationDelegate>
@property (nonatomic, copy) void(^onSuccess)(NSString *steamID64);
@end

@implementation SteamLoginVC { WKWebView *_webView; }
- (void)viewDidLoad {
    [super viewDidLoad];
    _webView = [[WKWebView alloc] initWithFrame:self.view.bounds];
    _webView.navigationDelegate = self;
    [self.view addSubview:_webView];

    NSString *realm = @"https://locationovo.github.io";
    NSString *returnTo = @"https://locationovo.github.io/steam-callback/";

    NSString *urlStr = [NSString stringWithFormat:
        @"https://steamcommunity.com/openid/login"
        @"?openid.ns=http://specs.openid.net/auth/2.0"
        @"&openid.mode=checkid_setup"
        @"&openid.return_to=%@"
        @"&openid.realm=%@"
        @"&openid.identity=http://specs.openid.net/auth/2.0/identifier_select"
        @"&openid.claimed_id=http://specs.openid.net/auth/2.0/identifier_select",
        returnTo, realm];

    [_webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlStr]]];
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void(^)(WKNavigationActionPolicy))handler {
    NSURL *url = action.request.URL;
    if ([url.absoluteString containsString:@"steam_callback"]) {
        NSURLComponents *comp = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        for (NSURLQueryItem *item in comp.queryItems) {
            if ([item.name isEqualToString:@"openid.claimed_id"]) {
                NSString *sid = [item.value componentsSeparatedByString:@"/"].lastObject;
                handler(WKNavigationActionPolicyCancel);
                if (self.onSuccess && sid) self.onSuccess(sid);
                return;
            }
        }
    }
    handler(WKNavigationActionPolicyAllow);
}
@end

// 验证逻辑
@interface Verifier : NSObject
+ (void)start;
+ (void)verify:(NSString *)steamID64;
+ (void)showLogin;
+ (void)showFailure;
+ (void)dismiss;
+ (void)setRootVC:(UIViewController *)vc;
@end

@implementation Verifier

+ (void)load {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self start]; });
}

+ (void)start {
    NSString *sid = [[NSUserDefaults standardUserDefaults] stringForKey:kSteamIDKey];
    if (sid.length > 0) {
        [self verify:sid];
    } else {
        [self showLogin];
    }
}

+ (void)verify:(NSString *)steamID64 {
    NSString *urlStr = [NSString stringWithFormat:@"https://steamcommunity.com/profiles/%@/games?tab=all", steamID64];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    [req setValue:@"Mozilla/5.0 (Windows NT 10.0; Win64; x64)" forHTTPHeaderField:@"User-Agent"];

    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (!data) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self showFailure]; });
            return;
        }
        NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"/store\\.steampowered\\.com/app/1671210/" options:0 error:nil];
        BOOL found = [re rangeOfFirstMatchInString:html options:0 range:NSMakeRange(0, html.length)].location != NSNotFound;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (found) {
                [[NSUserDefaults standardUserDefaults] setObject:steamID64 forKey:kSteamIDKey];
                [[NSUserDefaults standardUserDefaults] synchronize];
                [self dismiss];
            } else {
                [self showFailure];
            }
        });
    }] resume];
}

+ (void)showLogin {
    SteamLoginVC *vc = [[SteamLoginVC alloc] init];
    vc.onSuccess = ^(NSString *steamID64) {
        [[NSUserDefaults standardUserDefaults] setObject:steamID64 forKey:kSteamIDKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [self verify:steamID64];
    };
    [self setRootVC:vc];
}

+ (void)showFailure {
    FailureViewController *vc = [[FailureViewController alloc] init];
    vc.onRetry = ^{ [self showLogin]; };
    [self setRootVC:vc];
}

+ (void)dismiss {
    UIWindow *w = [UIApplication sharedApplication].keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
    UIStoryboard *sb = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    w.rootViewController = [sb instantiateInitialViewController];
    [w makeKeyAndVisible];
}

+ (void)setRootVC:(UIViewController *)vc {
    UIWindow *w = [UIApplication sharedApplication].keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
    w.rootViewController = [[UINavigationController alloc] initWithRootViewController:vc];
    [w makeKeyAndVisible];
}

@end
