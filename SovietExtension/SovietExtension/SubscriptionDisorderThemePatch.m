//
//  SubscriptionDisorderThemePatch.m
//  SovietExtension
//
//  A deliberately narrow patch for the Official Accounts feed LiteApp.
//

#import <Foundation/Foundation.h>

static NSString *const YMSubscriptionAppID = @"wxalite2fd372f050eecd471a4392786dfae78c";
static NSString *const YMSubscriptionBuild = @"10084";
static NSString *const YMSubscriptionPage = @"pkg/pages/s1s-subscription-index";
static NSString *const YMSubscriptionMarkerBegin = @"/* SovietExtension:SubscriptionDisorder begin */";
static NSString *const YMSubscriptionMarkerEnd = @"/* SovietExtension:SubscriptionDisorder end */";

static NSString *YMSubscriptionOverride(void)
{
    // These selectors are meaningful only in the exact page stylesheet above.
    // Avoid changing shared --BG-* variables or any other AppEx document.
    return [NSString stringWithFormat:@"\n%@\n.darkmode .bg-bg-0[data-v-5b3cbe12],.darkmode .page-scroll-view[data-v-5b3cbe12]{background-color:#1e1e2e!important}.darkmode .bg-bg-5{background-color:#313244!important}\n%@\n",
            YMSubscriptionMarkerBegin, YMSubscriptionMarkerEnd];
}

static BOOL YMIsExpectedSubscriptionPackage(NSString *pageDirectory)
{
    NSString *entryJS = [pageDirectory stringByAppendingPathComponent:@"entry.js"];
    NSData *data = [NSData dataWithContentsOfFile:entryJS options:NSDataReadingMappedIfSafe error:nil];
    if (!data) return NO;
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) return NO;

    // Fail closed if Tencent changes the route, page scope, or mount contract.
    return [text containsString:@"[s1s-subscription-index]"] &&
           [text containsString:@"data-v-5b3cbe12"] &&
           [text containsString:@"class:\"page-scroll-view relative\""] &&
           [text containsString:@"card-style-class\":\"bg-bg-5\""];
}

static BOOL YMPatchSubscriptionStylesheet(NSString *path)
{
    NSError *error = nil;
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    if (!text) return NO;

    // Scope and utility declarations prove this is the expected page output,
    // rather than an unrelated file with the same basename.
    if (![text containsString:@".page-scroll-view.data-v-5b3cbe12"] ||
        ![text containsString:@"linear-gradient(to top,var(--BG-5),var(--TRANSPARENT-BG-5))"]) {
        return NO;
    }

    NSRange begin = [text rangeOfString:YMSubscriptionMarkerBegin];
    NSRange end = [text rangeOfString:YMSubscriptionMarkerEnd];
    if ((begin.location == NSNotFound) != (end.location == NSNotFound)) return NO;
    if (begin.location != NSNotFound) {
        if (end.location < begin.location) return NO;
        NSUInteger endIndex = NSMaxRange(end);
        text = [text stringByReplacingCharactersInRange:NSMakeRange(begin.location, endIndex - begin.location)
                                             withString:@""];
    }

    text = [text stringByAppendingString:YMSubscriptionOverride()];
    return [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
}

static void YMPatchSubscriptionDisorderTheme(void)
{
    NSString *usersRoot = [NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Containers/com.tencent.xinWeChat/Data/Documents/app_data/radium/users"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *users = [fm contentsOfDirectoryAtPath:usersRoot error:nil];
    if (!users) return;

    for (NSString *user in users) {
        NSString *packagesRoot = [usersRoot stringByAppendingPathComponent:user];
        packagesRoot = [packagesRoot stringByAppendingPathComponent:@"xworker/liteapp/local/packages"];
        packagesRoot = [packagesRoot stringByAppendingPathComponent:YMSubscriptionAppID];
        packagesRoot = [packagesRoot stringByAppendingPathComponent:@"main"];
        NSArray<NSString *> *builds = [fm contentsOfDirectoryAtPath:packagesRoot error:nil];
        if (![builds containsObject:YMSubscriptionBuild]) continue;

        NSString *pageDirectory = [packagesRoot stringByAppendingPathComponent:YMSubscriptionBuild];
        pageDirectory = [pageDirectory stringByAppendingPathComponent:@"dist"];
        pageDirectory = [pageDirectory stringByAppendingPathComponent:YMSubscriptionPage];

        if (!YMIsExpectedSubscriptionPackage(pageDirectory)) continue;
        YMPatchSubscriptionStylesheet([pageDirectory stringByAppendingPathComponent:@"entry.css"]);
        YMPatchSubscriptionStylesheet([pageDirectory stringByAppendingPathComponent:@"entry.0.css"]);
    }
}

@interface YMSubscriptionDisorderThemePatch : NSObject
@end

@implementation YMSubscriptionDisorderThemePatch

+ (void)load
{
    // +load runs in the sandboxed WeChat host, before its AppEx feed is opened.
    YMPatchSubscriptionDisorderTheme();
}

@end
