#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "ApolloCommon.h"
#import "Tweak.h"
#import "UIWindow+Apollo.h"

// Fix pour le bug Logos "Invalid argument structure in %orig" avec les structs dans les blocks
typedef void (*TextNodeTappedImpl)(id, SEL, id, id, id, struct CGPoint, struct _NSRange);
#define CallOrig_TextNodeTapped(self, cmd, a, b, c, p, r) \
    ((TextNodeTappedImpl)objc_msgSend)(self, cmd, a, b, c, p, r)

// Regex for opaque share links
static NSString *const ShareLinkRegexPattern = @"^(?:https?:)?//(?:www\\.|new\\.|np\\.)?reddit\\.com/(?:r|u)/(\\w+)/s/(\\w+)$";
static NSRegularExpression *ShareLinkRegex;

// Regex for media share links
static NSString *const MediaShareLinkPattern = @"^(?:https?:)?//(?:www\\.|np\\.)?reddit\\.com/media\\?url=(.*?)$";
static NSRegularExpression *MediaShareLinkRegex;

// Regex for Imgur image links with title + ID
static NSString *const ImgurTitleIdImageLinkPattern = @"^(?:https?:)?//(?:www\\.)?imgur\\.com/(\\w+(?:-\\w+)+)$";
static NSRegularExpression *ImgurTitleIdImageLinkRegex;

// Regex for href extraction from HTML so we can preload share URLs from markdown/comment HTML bodies
static NSString *const HTMLHrefRegexPattern = @"href\\s*=\\s*(?:\"([^\"]+)\"|'([^']+)')";
static NSRegularExpression *HTMLHrefRegex;

// Cache storing resolved share URLs - this is an optimization so that we don't need to resolve the share URL every time
static NSCache<NSString *, ShareUrlTask *> *cache;

@implementation ShareUrlTask
- (instancetype)init {
    self = [super init];
    if (self) {
        _dispatchGroup = NULL;
        _resolvedURL = NULL;
    }
    return self;
}
@end

static BOOL ApolloIsShareLinkString(NSString *urlString) {
    if (![urlString isKindOfClass:[NSString class]] || urlString.length == 0 || !ShareLinkRegex) {
        return NO;
    }
    NSTextCheckingResult *match = [ShareLinkRegex firstMatchInString:urlString options:0 range:NSMakeRange(0, urlString.length)];
    return match != nil;
}

// Normalize share URL for use as cache key.
// Strips www./new./np. prefix so that e.g. "https://www.reddit.com/r/sub/s/abc"
// and "https://reddit.com/r/sub/s/abc" (from link button display text) hit the same entry.
static NSString *NormalizeShareURLCacheKey(NSString *urlString) {
    if (![urlString isKindOfClass:[NSString class]] || urlString.length == 0) {
        return urlString;
    }
    // Only normalize reddit share URLs
    NSRange range = [urlString rangeOfString:@"://www.reddit.com/"];
    if (range.location != NSNotFound) {
        return [urlString stringByReplacingCharactersInRange:range withString:@"://reddit.com/"];
    }
    range = [urlString rangeOfString:@"://new.reddit.com/"];
    if (range.location != NSNotFound) {
        return [urlString stringByReplacingCharactersInRange:range withString:@"://reddit.com/"];
    }
    range = [urlString rangeOfString:@"://np.reddit.com/"];
    if (range.location != NSNotFound) {
        return [urlString stringByReplacingCharactersInRange:range withString:@"://reddit.com/"];
    }
    return urlString;
}

%ctor {
    cache = [NSCache new];

    NSError *error = NULL;
    ShareLinkRegex = [NSRegularExpression regularExpressionWithPattern:ShareLinkRegexPattern options:NSRegularExpressionCaseInsensitive error:&error];
    MediaShareLinkRegex = [NSRegularExpression regularExpressionWithPattern:MediaShareLinkPattern options:NSRegularExpressionCaseInsensitive error:&error];
    ImgurTitleIdImageLinkRegex = [NSRegularExpression regularExpressionWithPattern:ImgurTitleIdImageLinkPattern options:NSRegularExpressionCaseInsensitive error:&error];
    HTMLHrefRegex = [NSRegularExpression regularExpressionWithPattern:HTMLHrefRegexPattern options:NSRegularExpressionCaseInsensitive error:&error];

    %init;
}
