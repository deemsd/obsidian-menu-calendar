#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <ServiceManagement/ServiceManagement.h>
#import <dispatch/dispatch.h>
#import <fcntl.h>
#import <math.h>
#import <unistd.h>

static CGFloat const OMCWidth = 310.0;
static CGFloat const OMCHeight = 640.0;
static NSUInteger const OMCVisibleCalendarRows = 5;
static NSString *const OMCDraggedTaskPasteboardType = @"com.deemsd.MenuCalendar.task";

static NSColor *OMCAccentColor(void);
static NSColor *OMCAccentSoftColor(void);
static NSColor *OMCSecondaryTextColor(void);
static NSColor *OMCDividerColor(void);
static NSColor *OMCPanelFillColor(void);
static NSColor *OMCHoverFillColor(void);
static NSColor *OMCTaskTintColor(void);
static NSColor *OMCOverdueColor(void);
static NSColor *OMCColorFromHex(NSString *hex, NSColor *fallback);
static NSString *OMCHexFromColor(NSColor *color);

@interface OMCFlippedView : NSView
@end

@implementation OMCFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface OMCInputPanel : NSPanel
@end

@implementation OMCInputPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end

@interface OMCColorBarView : NSView
@property (nonatomic, strong) NSColor *fillColor;
@end

@implementation OMCColorBarView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    [self.fillColor ?: OMCTaskTintColor() setFill];
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:2 yRadius:2];
    [path fill];
}
@end

@interface OMCRowBackgroundView : NSView
@property (nonatomic, assign) BOOL hovered;
@end

@implementation OMCRowBackgroundView {
    NSTrackingArea *_trackingArea;
}
- (BOOL)isFlipped { return YES; }
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}
- (void)mouseEntered:(NSEvent *)event {
    self.hovered = YES;
    self.needsDisplay = YES;
}
- (void)mouseExited:(NSEvent *)event {
    self.hovered = NO;
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    if (!self.hovered) {
        return;
    }
    [OMCHoverFillColor() setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 1.0) xRadius:7 yRadius:7] fill];
}
@end

@interface OMCEmptyStateView : NSView
@property (nonatomic, copy) NSString *text;
@end

@implementation OMCEmptyStateView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSColor *muted = [OMCSecondaryTextColor() colorWithAlphaComponent:0.64];
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: muted
    };
    [self.text ?: @"" drawAtPoint:NSMakePoint(2, 8) withAttributes:attrs];
}
@end

@interface OMCGlassOverlayView : NSView
@end

@implementation OMCGlassOverlayView
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return NO; }
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect bounds = NSInsetRect(self.bounds, 0.75, 0.75);
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:16 yRadius:16];
    [shape addClip];

    [[NSColor colorWithCalibratedRed:0.88 green:0.95 blue:1.0 alpha:0.34] setFill];
    [shape fill];

    NSGradient *verticalWash = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:1 alpha:0.24]
                                                            endingColor:[NSColor colorWithCalibratedRed:0.74 green:0.88 blue:1.0 alpha:0.10]];
    [verticalWash drawInRect:self.bounds angle:-90];

    NSGradient *bottomWarmth = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedRed:1.0 green:0.86 blue:0.72 alpha:0.08]
                                                            endingColor:[NSColor colorWithCalibratedWhite:1 alpha:0.0]];
    [bottomWarmth drawInRect:NSMakeRect(0, self.bounds.size.height * 0.70, self.bounds.size.width, self.bounds.size.height * 0.30) angle:90];

    [[NSColor colorWithCalibratedWhite:1 alpha:0.14] setFill];
    NSBezierPath *topSheen = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(13, 11, self.bounds.size.width - 26, 2.0) xRadius:1 yRadius:1];
    [topSheen fill];

    NSBezierPath *innerStroke = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 1, 1) xRadius:15 yRadius:15];
    innerStroke.lineWidth = 1.0;
    [[NSColor colorWithCalibratedWhite:1 alpha:0.16] setStroke];
    [innerStroke stroke];
}
@end

@interface OMCChromeButton : NSButton
@property (nonatomic, assign) BOOL pillStyle;
@property (nonatomic, strong) NSColor *accentColor;
@property (nonatomic, strong) NSColor *labelColor;
@property (nonatomic, assign) CGFloat labelSize;
@property (nonatomic, copy) NSString *fontName;
@property (nonatomic, assign) CGFloat fontWeight;
@end

@implementation OMCChromeButton
- (BOOL)acceptsFirstResponder { return NO; }
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.bordered = NO;
        self.focusRingType = NSFocusRingTypeNone;
        self.accentColor = OMCAccentColor();
        self.labelColor = OMCSecondaryTextColor();
        self.labelSize = 14;
        self.fontWeight = NSFontWeightMedium;
    }
    return self;
}
- (BOOL)isFlipped { return YES; }
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    if (self.pillStyle) {
        NSColor *fill = [self.accentColor colorWithAlphaComponent:self.highlighted ? 0.16 : 0.10];
        NSColor *stroke = [self.accentColor colorWithAlphaComponent:self.highlighted ? 0.38 : 0.24];
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5) xRadius:10 yRadius:10];
        [fill setFill];
        [path fill];
        path.lineWidth = 1;
        [stroke setStroke];
        [path stroke];
    }

    NSColor *textColor = self.pillStyle ? self.accentColor : self.labelColor;
    if (self.highlighted && !self.pillStyle) {
        textColor = [textColor colorWithAlphaComponent:0.65];
    }
    NSFont *font = self.fontName.length > 0 ? [NSFont fontWithName:self.fontName size:self.labelSize] : nil;
    if (!font) {
        font = [NSFont systemFontOfSize:self.labelSize weight:self.pillStyle ? NSFontWeightSemibold : self.fontWeight];
    }
    NSDictionary *attrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: textColor
    };
    NSSize size = [self.title sizeWithAttributes:attrs];
    CGFloat y = (self.bounds.size.height - size.height) / 2 - 0.5;
    [self.title drawAtPoint:NSMakePoint((self.bounds.size.width - size.width) / 2, y) withAttributes:attrs];
}
@end

@interface OMCRoundColorWell : NSColorWell
@end

@implementation OMCRoundColorWell
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.bordered = NO;
        self.focusRingType = NSFocusRingTypeNone;
    }
    return self;
}
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (void)mouseDown:(NSEvent *)event {
    [self.window makeFirstResponder:self];
    [self activate:YES];
}
- (void)setColor:(NSColor *)color {
    [super setColor:color];
    self.needsDisplay = YES;
}
- (void)deactivate {
    [super deactivate];
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    [NSGraphicsContext saveGraphicsState];

    CGFloat diameter = MIN(self.bounds.size.width, self.bounds.size.height) - 3.0;
    NSRect circleRect = NSMakeRect((self.bounds.size.width - diameter) / 2.0,
                                  (self.bounds.size.height - diameter) / 2.0,
                                  diameter,
                                  diameter);
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:circleRect];

    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [NSColor colorWithCalibratedWhite:0 alpha:0.16];
    shadow.shadowBlurRadius = 4;
    shadow.shadowOffset = NSMakeSize(0, -1);
    [shadow set];

    [[NSColor colorWithCalibratedWhite:1 alpha:0.72] setFill];
    [circle fill];

    [NSGraphicsContext restoreGraphicsState];

    NSBezierPath *insetCircle = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(circleRect, 3, 3)];
    [[self.color ?: OMCTaskTintColor() colorUsingColorSpace:NSColorSpace.sRGBColorSpace] setFill];
    [insetCircle fill];

    NSBezierPath *stroke = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(circleRect, 0.75, 0.75)];
    stroke.lineWidth = self.active ? 2.0 : 1.0;
    NSColor *strokeColor = self.active ? OMCAccentColor() : [NSColor colorWithCalibratedWhite:0 alpha:0.16];
    [strokeColor setStroke];
    [stroke stroke];
}
@end

@interface OMCTask : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *rawLine;
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, assign) NSInteger lineIndex;
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, assign) BOOL done;
@property (nonatomic, copy) NSArray<NSString *> *tags;
@property (nonatomic, copy, nullable) NSString *timeText;
@property (nonatomic, copy, nullable) NSString *recurrenceText;
@end

@implementation OMCTask
@end

@interface OMCTextFile : NSObject
@property (nonatomic, strong) NSMutableArray<NSString *> *lines;
@property (nonatomic, copy) NSString *newline;
@property (nonatomic, assign) BOOL hasTrailingNewline;
@end

@implementation OMCTextFile
@end

@interface OMCTaskCacheEntry : NSObject
@property (nonatomic, assign) BOOL exists;
@property (nonatomic, strong, nullable) NSDate *modificationDate;
@property (nonatomic, copy) NSArray<OMCTask *> *tasks;
@end

@implementation OMCTaskCacheEntry
@end

@class OMCConfig;
static NSString *OMCNotePathForDate(OMCConfig *config, NSDate *date);
static OMCTextFile *OMCCreateTextFileFromTemplate(OMCConfig *config, NSDate *date, NSError **error);

static NSColor *OMCAccentColor(void) {
    return [NSColor colorWithCalibratedRed:0.95 green:0.25 blue:0.32 alpha:1.0];
}

static NSColor *OMCAccentSoftColor(void) {
    return [NSColor colorWithCalibratedRed:1.0 green:0.92 blue:0.93 alpha:1.0];
}

static NSColor *OMCTextColor(void) {
    return [NSColor colorWithCalibratedRed:0.13 green:0.13 blue:0.16 alpha:1.0];
}

static NSColor *OMCSecondaryTextColor(void) {
    return [NSColor colorWithCalibratedRed:0.56 green:0.56 blue:0.62 alpha:1.0];
}

static NSColor *OMCDividerColor(void) {
    return [NSColor colorWithWhite:0 alpha:0.035];
}

static NSColor *OMCPanelFillColor(void) {
    return [NSColor clearColor];
}

static NSColor *OMCHoverFillColor(void) {
    return [NSColor colorWithCalibratedWhite:1 alpha:0.20];
}

static NSColor *OMCTaskTintColor(void) {
    NSColor *fallback = [NSColor colorWithCalibratedRed:0.42 green:0.31 blue:0.74 alpha:1.0];
    return OMCColorFromHex([NSUserDefaults.standardUserDefaults stringForKey:@"accentHexColor"], fallback);
}

static NSColor *OMCOverdueColor(void) {
    return [NSColor colorWithCalibratedRed:0.96 green:0.24 blue:0.30 alpha:1.0];
}

static NSArray<NSColor *> *OMCTagColors(void) {
    return @[
        [NSColor colorWithCalibratedRed:0.50 green:0.38 blue:0.78 alpha:1.0],
        OMCTaskTintColor(),
        [NSColor colorWithCalibratedRed:0.96 green:0.57 blue:0.16 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.08 green:0.68 blue:0.52 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.94 green:0.22 blue:0.48 alpha:1.0]
    ];
}

static NSColor *OMCColorForTask(OMCTask *task) {
    NSArray<NSColor *> *colors = OMCTagColors();
    if (task.tags.count == 0) {
        return colors[1];
    }
    NSUInteger index = labs((long)task.tags.firstObject.hash) % colors.count;
    return colors[index];
}

static NSCalendar *OMCCalendar(void) {
    static NSCalendar *calendar;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        calendar = [NSCalendar autoupdatingCurrentCalendar];
        calendar.firstWeekday = 1;
    });
    return calendar;
}

static NSDate *OMCStartOfDay(NSDate *date) {
    return [OMCCalendar() startOfDayForDate:date ?: [NSDate date]];
}

static NSDateFormatter *OMCDateFormatter(NSString *format) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = format;
    return formatter;
}

static NSString *OMCCanonicalDateKey(NSDate *date) {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = OMCDateFormatter(@"yyyy-MM-dd");
    });
    return [formatter stringFromDate:OMCStartOfDay(date)];
}

static NSString *OMCCompletionDateString(NSDate *date) {
    return OMCCanonicalDateKey(date);
}

static NSString *OMCDueDateString(NSDate *date) {
    return [NSString stringWithFormat:@"📅 %@", OMCCanonicalDateKey(date)];
}

static NSString *OMCMonthTitle(NSDate *date) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    formatter.dateFormat = @"yyyy年M月";
    return [formatter stringFromDate:date];
}

static NSString *OMCShortDate(NSDate *date) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.dateFormat = @"E, M月d日";
    return [formatter stringFromDate:date];
}

static NSString *OMCClipboardDateTitle(NSDate *date) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    formatter.dateFormat = @"M月d日";
    return [formatter stringFromDate:date];
}

static NSString *OMCLunarDayText(NSDate *date) {
    NSCalendar *lunarCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierChinese];
    NSDateComponents *components = [lunarCalendar components:NSCalendarUnitDay | NSCalendarUnitMonth fromDate:date];
    NSArray<NSString *> *days = @[
        @"初一", @"初二", @"初三", @"初四", @"初五", @"初六", @"初七", @"初八", @"初九", @"初十",
        @"十一", @"十二", @"十三", @"十四", @"十五", @"十六", @"十七", @"十八", @"十九", @"二十",
        @"廿一", @"廿二", @"廿三", @"廿四", @"廿五", @"廿六", @"廿七", @"廿八", @"廿九", @"三十"
    ];
    NSArray<NSString *> *months = @[@"正月", @"二月", @"三月", @"四月", @"五月", @"六月", @"七月", @"八月", @"九月", @"十月", @"冬月", @"腊月"];
    NSInteger day = components.day;
    NSInteger month = components.month;
    if (day == 1 && month >= 1 && month <= (NSInteger)months.count) {
        return months[(NSUInteger)month - 1];
    }
    if (day >= 1 && day <= (NSInteger)days.count) {
        return days[(NSUInteger)day - 1];
    }
    return @"";
}

static NSString *OMCGregorianHolidayText(NSDate *date) {
    NSDateComponents *components = [OMCCalendar() components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:date];
    if (components.month == 1 && components.day == 1) return @"元旦";
    if (components.month == 5 && components.day == 1) return @"劳动";
    if (components.month == 10 && components.day == 1) return @"国庆";
    return nil;
}

static BOOL OMCIsLunarNewYearsEve(NSDate *date) {
    NSCalendar *lunarCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierChinese];
    NSDate *nextDay = [OMCCalendar() dateByAddingUnit:NSCalendarUnitDay value:1 toDate:OMCStartOfDay(date) options:0];
    NSDateComponents *nextComponents = [lunarCalendar components:NSCalendarUnitDay | NSCalendarUnitMonth fromDate:nextDay];
    return nextComponents.month == 1 && nextComponents.day == 1;
}

static NSString *OMCLunarFestivalText(NSDate *date) {
    NSCalendar *lunarCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierChinese];
    NSDateComponents *components = [lunarCalendar components:NSCalendarUnitDay | NSCalendarUnitMonth fromDate:date];
    if (components.leapMonth) {
        return nil;
    }

    NSInteger month = components.month;
    NSInteger day = components.day;
    if (month == 1 && day == 1) return @"春节";
    if (month == 1 && day == 15) return @"元宵";
    if (month == 5 && day == 5) return @"端午";
    if (month == 7 && day == 7) return @"七夕";
    if (month == 8 && day == 15) return @"中秋";
    if (month == 9 && day == 9) return @"重阳";
    if (month == 12 && day == 8) return @"腊八";
    if (OMCIsLunarNewYearsEve(date)) return @"除夕";
    return nil;
}

static NSInteger OMCSolarTermDayForYear(NSUInteger year, NSUInteger termIndex) {
    static double termInfo[] = {
        5.4055, 20.12, 3.87, 18.74, 5.63, 20.646, 4.81, 20.1,
        5.52, 21.04, 5.678, 21.37, 7.108, 22.83, 7.5, 23.13,
        7.646, 23.042, 8.318, 23.438, 7.438, 22.36, 7.18, 21.94
    };
    NSInteger y = (NSInteger)(year % 100);
    return (NSInteger)floor(y * 0.2422 + termInfo[termIndex]) - (NSInteger)floor((y - 1) / 4.0);
}

static NSString *OMCSolarTermText(NSDate *date) {
    NSDateComponents *components = [OMCCalendar() components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:date];
    if (components.year < 2000 || components.year > 2099) {
        return nil;
    }

    NSArray<NSString *> *terms = @[
        @"小寒", @"大寒", @"立春", @"雨水", @"惊蛰", @"春分", @"清明", @"谷雨",
        @"立夏", @"小满", @"芒种", @"夏至", @"小暑", @"大暑", @"立秋", @"处暑",
        @"白露", @"秋分", @"寒露", @"霜降", @"立冬", @"小雪", @"大雪", @"冬至"
    ];
    NSUInteger firstTermIndex = (NSUInteger)(components.month - 1) * 2;
    for (NSUInteger offset = 0; offset < 2; offset++) {
        NSUInteger termIndex = firstTermIndex + offset;
        if (components.day == OMCSolarTermDayForYear((NSUInteger)components.year, termIndex)) {
            return terms[termIndex];
        }
    }
    return nil;
}

static NSString *OMCSpecialDayText(NSDate *date) {
    return OMCGregorianHolidayText(date) ?: OMCLunarFestivalText(date) ?: OMCSolarTermText(date);
}

static NSString *OMCDaySubtitleText(NSDate *date) {
    return OMCSpecialDayText(date) ?: OMCLunarDayText(date);
}

static NSRegularExpression *OMCRegex(NSString *pattern) {
    return [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
}

static NSString *OMCReplaceAll(NSString *text, NSString *pattern, NSString *replacement) {
    NSRegularExpression *regex = OMCRegex(pattern);
    NSRange range = NSMakeRange(0, text.length);
    return [regex stringByReplacingMatchesInString:text options:0 range:range withTemplate:replacement];
}

static NSString *OMCFirstCapture(NSString *text, NSString *pattern, NSUInteger group) {
    NSRegularExpression *regex = OMCRegex(pattern);
    NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!match || group >= match.numberOfRanges) {
        return nil;
    }
    NSRange range = [match rangeAtIndex:group];
    if (range.location == NSNotFound) {
        return nil;
    }
    return [text substringWithRange:range];
}

static NSString *OMCFirstCaptureWithOptions(NSString *text, NSString *pattern, NSUInteger group, NSRegularExpressionOptions options) {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:options error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!match || group >= match.numberOfRanges) {
        return nil;
    }
    NSRange range = [match rangeAtIndex:group];
    if (range.location == NSNotFound) {
        return nil;
    }
    return [text substringWithRange:range];
}

static NSArray<NSString *> *OMCAllCaptures(NSString *text, NSString *pattern, NSUInteger group) {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    NSRegularExpression *regex = OMCRegex(pattern);
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    for (NSTextCheckingResult *match in matches) {
        if (group < match.numberOfRanges) {
            NSRange range = [match rangeAtIndex:group];
            if (range.location != NSNotFound) {
                [values addObject:[text substringWithRange:range]];
            }
        }
    }
    return values;
}

static NSString *OMCCheckboxPattern(void) {
    return @"^(\\s*[-*+]\\s+\\[)([ xX])(\\]\\s+)(.*)$";
}

static NSString *OMCCompletionPattern(void) {
    return @"\\s*✅\\s*\\d{4}-\\d{2}-\\d{2}";
}

static NSString *OMCTagPattern(void) {
    return @"(?:^|\\s)#([\\p{L}\\p{N}_/-]+)";
}

static NSString *OMCTimePattern(void) {
    return @"(?<!\\d)([01]?\\d|2[0-3]):[0-5]\\d(?!\\d)";
}

static NSString *OMCTimeRangePattern(void) {
    return @"\\s*(?:[01]?\\d|2[0-3]):[0-5]\\d\\s*(?:[-–—~至到]\\s*)?(?:[01]?\\d|2[0-3]):[0-5]\\d";
}

static NSString *OMCDueDatePattern(void) {
    return @"📅\\s*\\d{4}-\\d{1,2}-\\d{1,2}";
}

static NSString *OMCRecurrencePattern(void) {
    return @"🔁\\s*((?:every\\s+)?\\d+\\s+(?:days?|weeks?|months?)|every\\s+(?:weekday|weekdays|days?|weeks?|months?)|每天|每日|每周|每月|工作日)";
}

static NSString *OMCRecurrenceTextFromBody(NSString *body) {
    NSString *text = OMCFirstCaptureWithOptions(body, OMCRecurrencePattern(), 1, NSRegularExpressionCaseInsensitive);
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *OMCRecurrenceKindFromText(NSString *text) {
    NSString *lower = text.lowercaseString ?: @"";
    if ([lower containsString:@"weekday"] || [lower containsString:@"工作日"]) {
        return @"weekday";
    }
    if ([lower containsString:@"week"] || [lower containsString:@"每周"]) {
        return @"week";
    }
    if ([lower containsString:@"month"] || [lower containsString:@"每月"]) {
        return @"month";
    }
    if ([lower containsString:@"day"] || [lower containsString:@"每天"] || [lower containsString:@"每日"]) {
        return @"day";
    }
    return nil;
}

static NSInteger OMCRecurrenceIntervalFromText(NSString *text) {
    NSString *number = OMCFirstCapture(text ?: @"", @"(?<!\\d)(\\d+)(?!\\d)", 1);
    NSInteger interval = number.integerValue;
    return interval > 0 ? interval : 1;
}

static NSDate *OMCDateFromDueDateInText(NSString *text) {
    NSRegularExpression *regex = OMCRegex(@"📅\\s*(\\d{4})-(\\d{1,2})-(\\d{1,2})");
    NSTextCheckingResult *match = [regex firstMatchInString:text ?: @"" options:0 range:NSMakeRange(0, text.length)];
    if (!match || match.numberOfRanges < 4) {
        return nil;
    }

    NSDateComponents *components = [[NSDateComponents alloc] init];
    components.calendar = OMCDateFormatter(@"yyyy-MM-dd").calendar;
    components.year = [[text substringWithRange:[match rangeAtIndex:1]] integerValue];
    components.month = [[text substringWithRange:[match rangeAtIndex:2]] integerValue];
    components.day = [[text substringWithRange:[match rangeAtIndex:3]] integerValue];
    return OMCStartOfDay([components.calendar dateFromComponents:components]);
}

static NSString *OMCStableIdentityFromTaskLine(NSString *line) {
    NSString *body = OMCFirstCapture(line, OMCCheckboxPattern(), 4);
    if (!body) {
        return nil;
    }
    NSString *withoutCompletion = OMCReplaceAll(body, OMCCompletionPattern(), @"");
    NSString *collapsed = OMCReplaceAll(withoutCompletion, @"\\s+", @" ");
    return [collapsed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *OMCVisibleTitleFromBody(NSString *body) {
    NSString *title = OMCReplaceAll(body, OMCCompletionPattern(), @"");
    title = OMCReplaceAll(title, OMCTagPattern(), @"");
    title = OMCReplaceAll(title, OMCDueDatePattern(), @"");
    title = OMCReplaceAll(title, OMCRecurrencePattern(), @"");
    title = OMCReplaceAll(title, @"✅\\s*\\d{4}-\\d{2}-\\d{2}", @"");
    title = OMCReplaceAll(title, OMCTimeRangePattern(), @" ");
    title = OMCReplaceAll(title, @"\\s*(?:[01]?\\d|2[0-3]):[0-5]\\d\\s*", @" ");
    title = OMCReplaceAll(title, @"\\s+", @" ");
    return [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static OMCTask *OMCParseTaskLine(NSString *line, NSInteger lineIndex, NSString *filePath, NSDate *date) {
    NSRegularExpression *regex = OMCRegex(OMCCheckboxPattern());
    NSTextCheckingResult *match = [regex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
    if (!match || match.numberOfRanges < 5) {
        return nil;
    }

    NSString *checkbox = [line substringWithRange:[match rangeAtIndex:2]];
    NSString *body = [line substringWithRange:[match rangeAtIndex:4]];
    NSMutableArray<NSString *> *tags = [NSMutableArray array];
    for (NSString *tag in OMCAllCaptures(body, OMCTagPattern(), 1)) {
        [tags addObject:[@"#" stringByAppendingString:tag]];
    }
    NSString *timeText = OMCFirstCapture(body, OMCTimePattern(), 0);
    NSString *recurrenceText = OMCRecurrenceTextFromBody(body);

    OMCTask *task = [[OMCTask alloc] init];
    task.title = OMCVisibleTitleFromBody(body);
    task.rawLine = line;
    task.filePath = filePath;
    task.lineIndex = lineIndex;
    task.date = OMCStartOfDay(date);
    task.done = [checkbox.lowercaseString isEqualToString:@"x"];
    task.tags = tags;
    task.timeText = timeText;
    task.recurrenceText = recurrenceText;
    task.identifier = [NSString stringWithFormat:@"%@#%ld#%@", filePath, (long)lineIndex, OMCStableIdentityFromTaskLine(line) ?: task.title ?: @""];
    return task;
}

static NSDate *OMCNextRecurrenceDate(OMCTask *task, NSDate *completionDate) {
    NSString *kind = OMCRecurrenceKindFromText(task.recurrenceText);
    if (kind.length == 0) {
        return nil;
    }

    NSCalendar *calendar = OMCCalendar();
    NSInteger interval = OMCRecurrenceIntervalFromText(task.recurrenceText);
    NSDate *completionDay = OMCStartOfDay(completionDate ?: [NSDate date]);
    NSDate *candidate = OMCStartOfDay(task.date ?: completionDay);

    if ([kind isEqualToString:@"day"]) {
        do {
            candidate = [calendar dateByAddingUnit:NSCalendarUnitDay value:interval toDate:candidate options:0];
        } while ([candidate compare:completionDay] != NSOrderedDescending);
        return candidate;
    }

    if ([kind isEqualToString:@"weekday"]) {
        do {
            candidate = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:candidate options:0];
            NSInteger weekday = [calendar component:NSCalendarUnitWeekday fromDate:candidate];
            while (weekday == 1 || weekday == 7) {
                candidate = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:candidate options:0];
                weekday = [calendar component:NSCalendarUnitWeekday fromDate:candidate];
            }
        } while ([candidate compare:completionDay] != NSOrderedDescending);
        return candidate;
    }

    if ([kind isEqualToString:@"week"]) {
        do {
            candidate = [calendar dateByAddingUnit:NSCalendarUnitDay value:7 * interval toDate:candidate options:0];
        } while ([candidate compare:completionDay] != NSOrderedDescending);
        return candidate;
    }

    if ([kind isEqualToString:@"month"]) {
        do {
            candidate = [calendar dateByAddingUnit:NSCalendarUnitMonth value:interval toDate:candidate options:0];
        } while ([candidate compare:completionDay] != NSOrderedDescending);
        return candidate;
    }

    return nil;
}

static NSString *OMCRecurringTaskBodyForNextDate(OMCTask *task, NSDate *nextDate) {
    NSString *body = OMCFirstCapture(task.rawLine ?: @"", OMCCheckboxPattern(), 4);
    if (body.length == 0 || !nextDate) {
        return nil;
    }

    body = OMCReplaceAll(body, OMCCompletionPattern(), @"");
    if (OMCFirstCapture(body, OMCDueDatePattern(), 0)) {
        body = OMCReplaceAll(body, OMCDueDatePattern(), OMCDueDateString(nextDate));
    } else {
        body = [body stringByAppendingFormat:@" %@", OMCDueDateString(nextDate)];
    }
    body = OMCReplaceAll(body, @"\\s+", @" ");
    return [body stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *OMCLineByReplacingCompletionState(NSString *line, BOOL done, NSDate *completionDate) {
    NSRegularExpression *regex = OMCRegex(OMCCheckboxPattern());
    NSTextCheckingResult *match = [regex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
    if (!match || match.numberOfRanges < 5) {
        return nil;
    }

    NSString *prefix = [line substringWithRange:[match rangeAtIndex:1]];
    NSString *suffix = [line substringWithRange:[match rangeAtIndex:3]];
    NSString *body = [line substringWithRange:[match rangeAtIndex:4]];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];

    if (done) {
        body = [body stringByTrimmingCharactersInSet:whitespace];
        if (!OMCFirstCapture(body, OMCCompletionPattern(), 0)) {
            body = [body stringByAppendingFormat:@" ✅ %@", OMCCompletionDateString(completionDate)];
        }
        return [NSString stringWithFormat:@"%@x%@%@", prefix, suffix, body];
    }

    body = OMCReplaceAll(body, OMCCompletionPattern(), @"");
    body = [body stringByTrimmingCharactersInSet:whitespace];
    return [NSString stringWithFormat:@"%@ %@%@", prefix, suffix, body];
}

static NSString *OMCTrimmedCollapsedText(NSString *text) {
    NSString *collapsed = OMCReplaceAll(text ?: @"", @"\\s+", @" ");
    return [collapsed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSColor *OMCColorFromHex(NSString *hex, NSColor *fallback) {
    NSString *clean = [[hex ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if ([clean hasPrefix:@"#"]) {
        clean = [clean substringFromIndex:1];
    }
    if (clean.length != 6) {
        return fallback;
    }

    unsigned int value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexInt:&value]) {
        return fallback;
    }

    CGFloat red = ((value >> 16) & 0xFF) / 255.0;
    CGFloat green = ((value >> 8) & 0xFF) / 255.0;
    CGFloat blue = (value & 0xFF) / 255.0;
    return [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1.0];
}

static NSString *OMCHexFromColor(NSColor *color) {
    NSColor *base = color ?: OMCTaskTintColor();
    NSColor *rgb = [base colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: OMCTaskTintColor();
    NSInteger red = MAX(0, MIN(255, (NSInteger)lround(rgb.redComponent * 255.0)));
    NSInteger green = MAX(0, MIN(255, (NSInteger)lround(rgb.greenComponent * 255.0)));
    NSInteger blue = MAX(0, MIN(255, (NSInteger)lround(rgb.blueComponent * 255.0)));
    return [NSString stringWithFormat:@"#%02lX%02lX%02lX", (long)red, (long)green, (long)blue];
}

static NSString *OMCEditableTextForTask(OMCTask *task) {
    NSString *body = OMCFirstCapture(task.rawLine ?: @"", OMCCheckboxPattern(), 4) ?: @"";
    body = OMCReplaceAll(body, OMCCompletionPattern(), @"");
    body = OMCReplaceAll(body, OMCDueDatePattern(), @"");
    body = OMCReplaceAll(body, OMCRecurrencePattern(), @"");
    body = OMCReplaceAll(body, OMCTagPattern(), @"");
    return OMCTrimmedCollapsedText(body);
}

static NSArray<NSString *> *OMCPreservedTaskSuffixParts(NSString *body) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *tag in OMCAllCaptures(body ?: @"", OMCTagPattern(), 1)) {
        [parts addObject:[@"#" stringByAppendingString:tag]];
    }

    NSString *dueDate = OMCFirstCapture(body ?: @"", OMCDueDatePattern(), 0);
    if (dueDate.length > 0) {
        [parts addObject:OMCTrimmedCollapsedText(dueDate)];
    }

    NSString *recurrence = OMCFirstCaptureWithOptions(body ?: @"", OMCRecurrencePattern(), 0, NSRegularExpressionCaseInsensitive);
    if (recurrence.length > 0) {
        [parts addObject:OMCTrimmedCollapsedText(recurrence)];
    }

    NSString *completion = OMCFirstCapture(body ?: @"", OMCCompletionPattern(), 0);
    if (completion.length > 0) {
        [parts addObject:OMCTrimmedCollapsedText(completion)];
    }
    return parts;
}

static NSString *OMCLineByReplacingTaskText(NSString *line, NSString *newText) {
    NSRegularExpression *regex = OMCRegex(OMCCheckboxPattern());
    NSTextCheckingResult *match = [regex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
    if (!match || match.numberOfRanges < 5) {
        return nil;
    }

    NSString *trimmed = OMCTrimmedCollapsedText(newText);
    if (trimmed.length == 0) {
        return nil;
    }

    NSString *prefix = [line substringWithRange:[match rangeAtIndex:1]];
    NSString *state = [line substringWithRange:[match rangeAtIndex:2]];
    NSString *suffix = [line substringWithRange:[match rangeAtIndex:3]];
    NSString *oldBody = [line substringWithRange:[match rangeAtIndex:4]];
    NSArray<NSString *> *parts = OMCPreservedTaskSuffixParts(oldBody);
    NSArray<NSString *> *newParts = parts.count > 0 ? [@[trimmed] arrayByAddingObjectsFromArray:parts] : @[trimmed];
    NSString *newBody = [newParts componentsJoinedByString:@" "];
    return [NSString stringWithFormat:@"%@%@%@%@", prefix, state, suffix, OMCTrimmedCollapsedText(newBody)];
}

static NSString *OMCLineByReplacingDueDate(NSString *line, NSDate *newDate) {
    NSRegularExpression *regex = OMCRegex(OMCCheckboxPattern());
    NSTextCheckingResult *match = [regex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
    if (!match || match.numberOfRanges < 5 || !newDate) {
        return nil;
    }

    NSString *prefix = [line substringWithRange:[match rangeAtIndex:1]];
    NSString *state = [line substringWithRange:[match rangeAtIndex:2]];
    NSString *suffix = [line substringWithRange:[match rangeAtIndex:3]];
    NSString *body = [line substringWithRange:[match rangeAtIndex:4]];
    NSString *newDueDate = OMCDueDateString(newDate);
    if (OMCFirstCapture(body, OMCDueDatePattern(), 0)) {
        body = OMCReplaceAll(body, OMCDueDatePattern(), newDueDate);
    } else {
        body = [body stringByAppendingFormat:@" %@", newDueDate];
    }
    return [NSString stringWithFormat:@"%@%@%@%@", prefix, state, suffix, OMCTrimmedCollapsedText(body)];
}

static OMCTextFile *OMCReadTextFile(NSString *path, NSError **error) {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:error];
    if (!text) {
        return nil;
    }

    NSString *newline = [text containsString:@"\r\n"] ? @"\r\n" : @"\n";
    BOOL trailing = [text hasSuffix:newline];
    NSString *body = trailing ? [text substringToIndex:text.length - newline.length] : text;

    OMCTextFile *file = [[OMCTextFile alloc] init];
    file.newline = newline;
    file.hasTrailingNewline = trailing;
    file.lines = body.length == 0 ? [NSMutableArray array] : [[body componentsSeparatedByString:newline] mutableCopy];
    return file;
}

static NSString *OMCRenderTextFile(OMCTextFile *file) {
    NSString *text = [file.lines componentsJoinedByString:file.newline ?: @"\n"];
    if (file.hasTrailingNewline) {
        text = [text stringByAppendingString:file.newline ?: @"\n"];
    }
    return text;
}

static BOOL OMCLineIsTodayTaskHeading(NSString *line) {
    return OMCFirstCapture(line, @"^\\s*###\\s+今日任务\\s*$", 0) != nil;
}

static NSInteger OMCMarkdownHeadingLevel(NSString *line) {
    NSString *markers = OMCFirstCapture(line, @"^\\s{0,3}(#{1,6})\\s+", 1);
    return markers.length > 0 ? (NSInteger)markers.length : NSNotFound;
}

static BOOL OMCLineIsBlank(NSString *line) {
    return [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0;
}

static BOOL OMCAppendTaskToDailyNote(OMCConfig *config, NSDate *date, NSString *taskText, NSError **error) {
    NSString *trimmed = [taskText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"ObsidianMenuCalendar" code:4 userInfo:@{NSLocalizedDescriptionKey: @"任务内容不能为空。"}];
        }
        return NO;
    }

    NSString *path = OMCNotePathForDate(config, date);
    NSString *directory = path.stringByDeletingLastPathComponent;
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }

    OMCTextFile *file = nil;
    if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
        file = OMCReadTextFile(path, error);
        if (!file) {
            return NO;
        }
    } else {
        file = OMCCreateTextFileFromTemplate(config, date, error);
        if (!file) {
            file = [[OMCTextFile alloc] init];
            file.lines = [NSMutableArray array];
            file.newline = @"\n";
            file.hasTrailingNewline = YES;
        }
    }

    NSString *taskBody = trimmed;
    if (!OMCFirstCapture(taskBody, OMCDueDatePattern(), 0)) {
        taskBody = [taskBody stringByAppendingFormat:@" %@", OMCDueDateString(date)];
    }
    NSString *taskLine = [NSString stringWithFormat:@"- [ ] %@", taskBody];
    NSInteger headingIndex = NSNotFound;
    for (NSUInteger index = 0; index < file.lines.count; index++) {
        if (OMCLineIsTodayTaskHeading(file.lines[index])) {
            headingIndex = (NSInteger)index;
            break;
        }
    }

    if (headingIndex == NSNotFound) {
        if (file.lines.count > 0 && !OMCLineIsBlank(file.lines.lastObject)) {
            [file.lines addObject:@""];
        }
        [file.lines addObject:@"### 今日任务"];
        [file.lines addObject:@""];
        [file.lines addObject:taskLine];
        file.hasTrailingNewline = YES;
        return [OMCRenderTextFile(file) writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
    }

    NSInteger sectionStart = headingIndex + 1;
    NSInteger sectionEnd = (NSInteger)file.lines.count;
    NSInteger lastTaskIndex = NSNotFound;
    for (NSInteger index = sectionStart; index < (NSInteger)file.lines.count; index++) {
        NSInteger headingLevel = OMCMarkdownHeadingLevel(file.lines[(NSUInteger)index]);
        if (headingLevel != NSNotFound && headingLevel <= 3) {
            sectionEnd = index;
            break;
        }
        if (OMCFirstCapture(file.lines[(NSUInteger)index], OMCCheckboxPattern(), 0) != nil) {
            lastTaskIndex = index;
        }
    }

    NSInteger insertIndex = sectionStart;
    if (lastTaskIndex != NSNotFound) {
        insertIndex = lastTaskIndex + 1;
    }

    [file.lines insertObject:taskLine atIndex:(NSUInteger)insertIndex];
    file.hasTrailingNewline = YES;
    return [OMCRenderTextFile(file) writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
}

static BOOL OMCAppendTaskLineToDailyNote(OMCConfig *config, NSDate *date, NSString *taskLine, NSError **error) {
    NSString *trimmedLine = [taskLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (OMCFirstCapture(trimmedLine, OMCCheckboxPattern(), 0).length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"ObsidianMenuCalendar" code:13 userInfo:@{NSLocalizedDescriptionKey: @"拖动的内容不是有效任务。"}];
        }
        return NO;
    }

    NSString *path = OMCNotePathForDate(config, date);
    NSString *directory = path.stringByDeletingLastPathComponent;
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }

    OMCTextFile *file = nil;
    if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
        file = OMCReadTextFile(path, error);
        if (!file) {
            return NO;
        }
    } else {
        file = OMCCreateTextFileFromTemplate(config, date, error);
        if (!file) {
            file = [[OMCTextFile alloc] init];
            file.lines = [NSMutableArray array];
            file.newline = @"\n";
            file.hasTrailingNewline = YES;
        }
    }

    NSInteger headingIndex = NSNotFound;
    for (NSUInteger index = 0; index < file.lines.count; index++) {
        if (OMCLineIsTodayTaskHeading(file.lines[index])) {
            headingIndex = (NSInteger)index;
            break;
        }
    }

    if (headingIndex == NSNotFound) {
        if (file.lines.count > 0 && !OMCLineIsBlank(file.lines.lastObject)) {
            [file.lines addObject:@""];
        }
        [file.lines addObject:@"### 今日任务"];
        [file.lines addObject:@""];
        [file.lines addObject:trimmedLine];
        file.hasTrailingNewline = YES;
        return [OMCRenderTextFile(file) writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
    }

    NSInteger sectionStart = headingIndex + 1;
    NSInteger lastTaskIndex = NSNotFound;
    for (NSInteger index = sectionStart; index < (NSInteger)file.lines.count; index++) {
        NSInteger headingLevel = OMCMarkdownHeadingLevel(file.lines[(NSUInteger)index]);
        if (headingLevel != NSNotFound && headingLevel <= 3) {
            break;
        }
        if (OMCFirstCapture(file.lines[(NSUInteger)index], OMCCheckboxPattern(), 0) != nil) {
            lastTaskIndex = index;
        }
    }

    NSInteger insertIndex = lastTaskIndex != NSNotFound ? lastTaskIndex + 1 : sectionStart;
    [file.lines insertObject:trimmedLine atIndex:(NSUInteger)insertIndex];
    file.hasTrailingNewline = YES;
    return [OMCRenderTextFile(file) writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
}

static BOOL OMCAppendTaskToMarkdownFile(NSString *path, NSString *taskText, NSError **error) {
    NSString *trimmed = [taskText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"ObsidianMenuCalendar" code:4 userInfo:@{NSLocalizedDescriptionKey: @"任务内容不能为空。"}];
        }
        return NO;
    }

    NSString *directory = path.stringByDeletingLastPathComponent;
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }

    OMCTextFile *file = nil;
    if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
        file = OMCReadTextFile(path, error);
        if (!file) {
            return NO;
        }
    } else {
        file = [[OMCTextFile alloc] init];
        file.lines = [NSMutableArray array];
        file.newline = @"\n";
        file.hasTrailingNewline = YES;
    }

    NSString *taskLine = [NSString stringWithFormat:@"- [ ] %@", trimmed];
    NSInteger lastTaskIndex = NSNotFound;
    for (NSUInteger index = 0; index < file.lines.count; index++) {
        if (OMCFirstCapture(file.lines[index], OMCCheckboxPattern(), 0) != nil) {
            lastTaskIndex = (NSInteger)index;
        }
    }

    if (lastTaskIndex != NSNotFound) {
        [file.lines insertObject:taskLine atIndex:(NSUInteger)lastTaskIndex + 1];
    } else {
        if (file.lines.count > 0 && !OMCLineIsBlank(file.lines.lastObject)) {
            [file.lines addObject:@""];
        }
        [file.lines addObject:taskLine];
    }

    file.hasTrailingNewline = YES;
    return [OMCRenderTextFile(file) writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
}

@interface OMCConfig : NSObject
@property (nonatomic, copy) NSString *vaultPath;
@property (nonatomic, copy) NSString *dailyFolder;
@property (nonatomic, copy) NSString *dateFormat;
@property (nonatomic, copy) NSString *accentHexColor;
@property (nonatomic, assign) NSInteger lookAheadDays;
@property (nonatomic, assign) NSInteger dotThresholdOne;
@property (nonatomic, assign) NSInteger dotThresholdTwo;
@property (nonatomic, assign) NSInteger dotThresholdThree;
@end

@implementation OMCConfig
- (instancetype)init {
    self = [super init];
    if (self) {
        _vaultPath = @"";
        _dailyFolder = @"";
        _dateFormat = @"yyyy-MM-dd";
        _accentHexColor = @"#6B4FBD";
        _lookAheadDays = 14;
        _dotThresholdOne = 1;
        _dotThresholdTwo = 4;
        _dotThresholdThree = 9;
    }
    return self;
}
- (BOOL)hasVault {
    return [self.vaultPath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0;
}
- (NSString *)expandedVaultPath {
    return [self.vaultPath stringByExpandingTildeInPath];
}
- (NSString *)dailyNotesPath {
    return self.expandedVaultPath;
}
@end

static OMCConfig *OMCLoadConfig(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    OMCConfig *config = [[OMCConfig alloc] init];
    NSString *vaultPath = [defaults stringForKey:@"vaultPath"];
    NSString *dailyFolder = [defaults stringForKey:@"dailyNotesFolder"];
    NSString *dateFormat = [defaults stringForKey:@"dateFormat"];
    NSString *accentHexColor = [defaults stringForKey:@"accentHexColor"];
    NSInteger lookAhead = [defaults integerForKey:@"lookAheadDays"];
    NSInteger dotOne = [defaults integerForKey:@"dotThresholdOne"];
    NSInteger dotTwo = [defaults integerForKey:@"dotThresholdTwo"];
    NSInteger dotThree = [defaults integerForKey:@"dotThresholdThree"];
    if (vaultPath) config.vaultPath = vaultPath;
    if (dailyFolder) config.dailyFolder = dailyFolder;
    if (dateFormat) config.dateFormat = dateFormat;
    if (accentHexColor) config.accentHexColor = accentHexColor;
    if (lookAhead > 0) config.lookAheadDays = lookAhead;
    if (dotOne > 0) config.dotThresholdOne = dotOne;
    if (dotTwo > 0) config.dotThresholdTwo = dotTwo;
    if (dotThree > 0) config.dotThresholdThree = dotThree;
    return config;
}

static void OMCSaveConfig(OMCConfig *config) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:config.vaultPath ?: @"" forKey:@"vaultPath"];
    [defaults setObject:config.dailyFolder ?: @"" forKey:@"dailyNotesFolder"];
    [defaults setObject:config.dateFormat ?: @"yyyy-MM-dd" forKey:@"dateFormat"];
    [defaults setObject:config.accentHexColor ?: @"#6B4FBD" forKey:@"accentHexColor"];
    [defaults setInteger:config.lookAheadDays forKey:@"lookAheadDays"];
    [defaults setInteger:config.dotThresholdOne forKey:@"dotThresholdOne"];
    [defaults setInteger:config.dotThresholdTwo forKey:@"dotThresholdTwo"];
    [defaults setInteger:config.dotThresholdThree forKey:@"dotThresholdThree"];
}

static BOOL OMCLoginItemEnabled(void) {
    if (@available(macOS 13.0, *)) {
        return SMAppService.mainAppService.status == SMAppServiceStatusEnabled;
    }
    return NO;
}

static BOOL OMCSetLoginItemEnabled(BOOL enabled, NSError **error) {
    if (@available(macOS 13.0, *)) {
        SMAppService *service = SMAppService.mainAppService;
        if (enabled) {
            if (service.status == SMAppServiceStatusEnabled) {
                return YES;
            }
            return [service registerAndReturnError:error];
        }

        if (service.status == SMAppServiceStatusNotRegistered) {
            return YES;
        }
        return [service unregisterAndReturnError:error];
    }

    if (error) {
        *error = [NSError errorWithDomain:@"ObsidianMenuCalendar" code:20 userInfo:@{NSLocalizedDescriptionKey: @"当前 macOS 版本不支持应用内设置开机启动。"}];
    }
    return NO;
}

static NSMutableDictionary<NSString *, NSString *> *OMCResolvedDailyNotesPathCache(void) {
    static NSMutableDictionary<NSString *, NSString *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
    });
    return cache;
}

static void OMCClearResolvedDailyNotesPathCache(void) {
    [OMCResolvedDailyNotesPathCache() removeAllObjects];
}

static BOOL OMCDailyNoteFileNameMatchesFormat(NSString *fileName, NSString *dateFormat) {
    if (![fileName.pathExtension.lowercaseString isEqualToString:@"md"]) {
        return NO;
    }

    NSString *baseName = fileName.stringByDeletingPathExtension;
    NSDateFormatter *formatter = OMCDateFormatter(dateFormat.length > 0 ? dateFormat : @"yyyy-MM-dd");
    formatter.lenient = NO;
    NSDate *date = [formatter dateFromString:baseName];
    return date != nil && [[formatter stringFromDate:date] isEqualToString:baseName];
}

static NSInteger OMCDailyFolderNameScore(NSString *path) {
    NSString *name = path.lastPathComponent.lowercaseString;
    if ([name containsString:@"每日记录"]) return 140;
    if ([name containsString:@"每日"]) return 120;
    if ([name containsString:@"日记"]) return 110;
    if ([name containsString:@"daily"]) return 105;
    if ([name containsString:@"journal"]) return 95;
    if ([name containsString:@"记录"]) return 55;
    return 0;
}

static NSInteger OMCMatchingDailyNoteCountInFolder(NSString *folder, NSString *dateFormat) {
    NSArray<NSString *> *children = [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil];
    NSInteger count = 0;
    for (NSString *child in children) {
        if (OMCDailyNoteFileNameMatchesFormat(child, dateFormat)) {
            count += 1;
        }
    }
    return count;
}

static NSString *OMCResolvedDailyNotesPath(OMCConfig *config) {
    NSString *basePath = [config.dailyNotesPath stringByStandardizingPath];
    NSString *dateFormat = config.dateFormat.length > 0 ? config.dateFormat : @"yyyy-MM-dd";
    NSString *cacheKey = [NSString stringWithFormat:@"%@|%@|%@", basePath ?: @"", config.dailyFolder ?: @"", dateFormat];
    NSString *cached = OMCResolvedDailyNotesPathCache()[cacheKey];
    if (cached.length > 0) {
        return cached;
    }

    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:basePath isDirectory:&isDirectory] || !isDirectory) {
        return basePath;
    }

    NSString *explicitFolder = [config.dailyFolder stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSInteger directCount = OMCMatchingDailyNoteCountInFolder(basePath, dateFormat);
    if (explicitFolder.length > 0 || directCount > 0 || OMCDailyFolderNameScore(basePath) >= 95) {
        OMCResolvedDailyNotesPathCache()[cacheKey] = basePath;
        return basePath;
    }

    NSMutableDictionary<NSString *, NSNumber *> *noteCountsByFolder = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *namedCandidates = [NSMutableSet set];
    NSDirectoryEnumerator<NSURL *> *enumerator = [NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:basePath]
                                                                    includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                                                       options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                  errorHandler:nil];
    NSUInteger scanned = 0;
    for (NSURL *url in enumerator) {
        scanned += 1;
        if (scanned > 8000) {
            break;
        }

        NSNumber *isDir = nil;
        [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        if (isDir.boolValue) {
            if (OMCDailyFolderNameScore(url.path) > 0) {
                [namedCandidates addObject:url.path];
            }
            continue;
        }

        if (!OMCDailyNoteFileNameMatchesFormat(url.lastPathComponent, dateFormat)) {
            continue;
        }

        NSString *folder = url.path.stringByDeletingLastPathComponent;
        NSInteger count = noteCountsByFolder[folder].integerValue + 1;
        noteCountsByFolder[folder] = @(count);
    }

    NSString *bestPath = nil;
    NSInteger bestScore = NSIntegerMin;
    for (NSString *folder in noteCountsByFolder) {
        NSInteger score = noteCountsByFolder[folder].integerValue * 10 + OMCDailyFolderNameScore(folder);
        if (score > bestScore) {
            bestScore = score;
            bestPath = folder;
        }
    }

    for (NSString *folder in namedCandidates) {
        NSInteger score = OMCDailyFolderNameScore(folder);
        if (score > bestScore) {
            bestScore = score;
            bestPath = folder;
        }
    }

    NSString *resolved = bestPath.length > 0 ? bestPath : basePath;
    OMCResolvedDailyNotesPathCache()[cacheKey] = resolved;
    return resolved;
}

static NSInteger OMCDailyNoteFileScore(NSString *path, NSString *basePath) {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSUInteger taskCount = [OMCRegex(OMCCheckboxPattern()) numberOfMatchesInString:text options:0 range:NSMakeRange(0, text.length)];
    NSUInteger nonBlankCount = 0;
    for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if ([line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0) {
            nonBlankCount += 1;
        }
    }

    NSString *relative = [path hasPrefix:basePath] ? [path substringFromIndex:basePath.length] : path;
    NSUInteger depth = [[relative componentsSeparatedByString:@"/"] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *part, NSDictionary *bindings) {
        return part.length > 0;
    }]].count;
    return (NSInteger)taskCount * 100000 + (NSInteger)nonBlankCount * 10 + (NSInteger)depth;
}

static NSString *OMCExistingChildDirectory(NSString *parent, NSArray<NSString *> *names) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    for (NSString *name in names) {
        NSString *path = [parent stringByAppendingPathComponent:name];
        BOOL isDirectory = NO;
        if ([fileManager fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
            return path;
        }
    }
    return nil;
}

static NSString *OMCPreferredMonthlyFolderForDate(NSString *basePath, NSDate *date) {
    NSString *year = [OMCDateFormatter(@"yyyy") stringFromDate:date];
    NSString *yearCN = [OMCDateFormatter(@"yyyy年") stringFromDate:date];
    NSString *month = [OMCDateFormatter(@"yyyy-MM") stringFromDate:date];
    NSString *monthLoose = [OMCDateFormatter(@"yyyy-M") stringFromDate:date];
    NSString *monthCN = [OMCDateFormatter(@"yyyy年MM月") stringFromDate:date];
    NSString *monthLooseCN = [OMCDateFormatter(@"yyyy年M月") stringFromDate:date];
    NSString *monthNumber = [OMCDateFormatter(@"MM") stringFromDate:date];
    NSString *monthNumberLoose = [OMCDateFormatter(@"M") stringFromDate:date];
    NSString *monthNumberCN = [OMCDateFormatter(@"MM月") stringFromDate:date];
    NSString *monthNumberLooseCN = [OMCDateFormatter(@"M月") stringFromDate:date];

    NSArray<NSString *> *yearNames = @[year, yearCN];
    NSString *yearPath = OMCExistingChildDirectory(basePath, yearNames);
    if (yearPath.length == 0) {
        yearPath = [basePath stringByAppendingPathComponent:year];
    }

    NSArray<NSString *> *monthNames = @[month, monthLoose, monthCN, monthLooseCN, monthNumber, monthNumberLoose, monthNumberCN, monthNumberLooseCN];
    NSString *monthPath = OMCExistingChildDirectory(yearPath, monthNames);
    if (monthPath.length == 0) {
        monthPath = [yearPath stringByAppendingPathComponent:month];
    }
    return monthPath;
}

static NSString *OMCNotePathForDate(OMCConfig *config, NSDate *date) {
    NSDateFormatter *formatter = OMCDateFormatter(config.dateFormat.length > 0 ? config.dateFormat : @"yyyy-MM-dd");
    NSString *fileName = [[formatter stringFromDate:date] stringByAppendingPathExtension:@"md"];
    NSString *basePath = [config.dailyNotesPath stringByStandardizingPath];
    NSString *year = [OMCDateFormatter(@"yyyy") stringFromDate:date];
    NSString *month = [OMCDateFormatter(@"yyyy-MM") stringFromDate:date];
    NSString *monthLoose = [OMCDateFormatter(@"yyyy-M") stringFromDate:date];
    NSString *monthNumber = [OMCDateFormatter(@"MM") stringFromDate:date];
    NSString *monthNumberLoose = [OMCDateFormatter(@"M") stringFromDate:date];
    NSString *yearCN = [OMCDateFormatter(@"yyyy年") stringFromDate:date];
    NSString *monthCN = [OMCDateFormatter(@"yyyy年MM月") stringFromDate:date];
    NSString *monthLooseCN = [OMCDateFormatter(@"yyyy年M月") stringFromDate:date];
    NSString *monthNumberCN = [OMCDateFormatter(@"MM月") stringFromDate:date];
    NSString *monthNumberLooseCN = [OMCDateFormatter(@"M月") stringFromDate:date];

    NSArray<NSString *> *candidates = @[
        [[basePath stringByAppendingPathComponent:year] stringByAppendingPathComponent:[month stringByAppendingPathComponent:fileName]],
        [[basePath stringByAppendingPathComponent:year] stringByAppendingPathComponent:[monthLoose stringByAppendingPathComponent:fileName]],
        [[basePath stringByAppendingPathComponent:year] stringByAppendingPathComponent:[monthNumber stringByAppendingPathComponent:fileName]],
        [[basePath stringByAppendingPathComponent:year] stringByAppendingPathComponent:[monthNumberLoose stringByAppendingPathComponent:fileName]],
        [[basePath stringByAppendingPathComponent:year] stringByAppendingPathComponent:[monthCN stringByAppendingPathComponent:fileName]],
        [[basePath stringByAppendingPathComponent:year] stringByAppendingPathComponent:[monthLooseCN stringByAppendingPathComponent:fileName]],
        [[basePath stringByAppendingPathComponent:year] stringByAppendingPathComponent:[monthNumberCN stringByAppendingPathComponent:fileName]],
        [[basePath stringByAppendingPathComponent:year] stringByAppendingPathComponent:[monthNumberLooseCN stringByAppendingPathComponent:fileName]],
        [[basePath stringByAppendingPathComponent:yearCN] stringByAppendingPathComponent:[month stringByAppendingPathComponent:fileName]],
        [[basePath stringByAppendingPathComponent:yearCN] stringByAppendingPathComponent:[monthLoose stringByAppendingPathComponent:fileName]],
        [[basePath stringByAppendingPathComponent:yearCN] stringByAppendingPathComponent:[monthNumber stringByAppendingPathComponent:fileName]],
        [[basePath stringByAppendingPathComponent:yearCN] stringByAppendingPathComponent:[monthNumberLoose stringByAppendingPathComponent:fileName]],
        [[basePath stringByAppendingPathComponent:yearCN] stringByAppendingPathComponent:[monthCN stringByAppendingPathComponent:fileName]],
        [[basePath stringByAppendingPathComponent:yearCN] stringByAppendingPathComponent:[monthLooseCN stringByAppendingPathComponent:fileName]],
        [[basePath stringByAppendingPathComponent:yearCN] stringByAppendingPathComponent:[monthNumberCN stringByAppendingPathComponent:fileName]],
        [[basePath stringByAppendingPathComponent:yearCN] stringByAppendingPathComponent:[monthNumberLooseCN stringByAppendingPathComponent:fileName]],
        [basePath stringByAppendingPathComponent:fileName]
    ];

    NSString *bestExisting = nil;
    NSInteger bestExistingScore = NSIntegerMin;
    for (NSString *candidate in candidates) {
        BOOL isDirectory = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:candidate isDirectory:&isDirectory] && !isDirectory) {
            NSInteger score = OMCDailyNoteFileScore(candidate, basePath);
            if (score > bestExistingScore) {
                bestExistingScore = score;
                bestExisting = candidate;
            }
        }
    }
    if (bestExisting.length > 0) {
        return bestExisting;
    }

    NSString *cacheKey = [NSString stringWithFormat:@"note|%@|%@|%@", basePath ?: @"", config.dateFormat ?: @"", fileName];
    NSString *cached = OMCResolvedDailyNotesPathCache()[cacheKey];
    if (cached.length > 0) {
        BOOL isDirectory = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:cached isDirectory:&isDirectory] && !isDirectory) {
            return cached;
        }
        [OMCResolvedDailyNotesPathCache() removeObjectForKey:cacheKey];
    }

    NSDirectoryEnumerator<NSURL *> *enumerator = [NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:basePath]
                                                                    includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                                                       options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                  errorHandler:nil];
    NSUInteger scanned = 0;
    for (NSURL *url in enumerator) {
        scanned += 1;
        if (scanned > 8000) {
            break;
        }

        NSNumber *isDir = nil;
        [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        if (isDir.boolValue) {
            NSString *name = url.lastPathComponent;
            if ([name isEqualToString:@".obsidian"] || [name isEqualToString:@".trash"] || [name isEqualToString:@"附件"] || [name.lowercaseString isEqualToString:@"attachments"]) {
                [enumerator skipDescendants];
            }
            continue;
        }

        if ([url.lastPathComponent isEqualToString:fileName]) {
            NSInteger score = OMCDailyNoteFileScore(url.path, basePath);
            if (score > bestExistingScore) {
                bestExistingScore = score;
                bestExisting = url.path;
            }
        }
    }
    if (bestExisting.length > 0) {
        OMCResolvedDailyNotesPathCache()[cacheKey] = bestExisting;
        return bestExisting;
    }

    return [OMCPreferredMonthlyFolderForDate(basePath, date) stringByAppendingPathComponent:fileName];
}

static NSString *OMCTaskCacheKey(NSString *path, NSDate *date) {
    return [NSString stringWithFormat:@"%@|%@", path ?: @"", OMCCanonicalDateKey(date)];
}

static BOOL OMCNullableDatesEqual(NSDate *left, NSDate *right) {
    if (!left && !right) {
        return YES;
    }
    if (!left || !right) {
        return NO;
    }
    return [left isEqualToDate:right];
}

static OMCTextFile *OMCTextFileFromString(NSString *text) {
    NSString *newline = [text containsString:@"\r\n"] ? @"\r\n" : @"\n";
    BOOL trailing = [text hasSuffix:newline];
    NSString *body = trailing ? [text substringToIndex:text.length - newline.length] : text;

    OMCTextFile *file = [[OMCTextFile alloc] init];
    file.newline = newline;
    file.hasTrailingNewline = YES;
    file.lines = body.length == 0 ? [NSMutableArray array] : [[body componentsSeparatedByString:newline] mutableCopy];
    if (!trailing && file.lines.count > 0) {
        file.hasTrailingNewline = YES;
    }
    return file;
}

static NSString *OMCVaultRootForConfig(OMCConfig *config) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSString *path = config.expandedVaultPath;
    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) {
        path = path.stringByDeletingLastPathComponent;
    }

    while (path.length > 1) {
        NSString *obsidianPath = [path stringByAppendingPathComponent:@".obsidian"];
        BOOL obsidianIsDirectory = NO;
        if ([fileManager fileExistsAtPath:obsidianPath isDirectory:&obsidianIsDirectory] && obsidianIsDirectory) {
            return path;
        }
        NSString *parent = path.stringByDeletingLastPathComponent;
        if ([parent isEqualToString:path]) {
            break;
        }
        path = parent;
    }
    return config.expandedVaultPath;
}

static NSDictionary *OMCJSONDictionaryAtPath(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        return nil;
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [object isKindOfClass:NSDictionary.class] ? object : nil;
}

static NSString *OMCDateTemplateString(NSDate *date, NSString *format) {
    NSString *dateFormat = format.length > 0 ? format : @"yyyy-MM-dd";
    dateFormat = [dateFormat stringByReplacingOccurrencesOfString:@"YYYY" withString:@"yyyy"];
    dateFormat = [dateFormat stringByReplacingOccurrencesOfString:@"DD" withString:@"dd"];
    NSDateFormatter *formatter = OMCDateFormatter(dateFormat);
    return [formatter stringFromDate:date];
}

static NSString *OMCRenderDailyTemplate(NSString *templateText, NSDate *date) {
    NSMutableString *rendered = [templateText mutableCopy];
    NSString *defaultDate = OMCDateTemplateString(date, @"yyyy-MM-dd");
    [rendered replaceOccurrencesOfString:@"{{date}}" withString:defaultDate options:0 range:NSMakeRange(0, rendered.length)];
    [rendered replaceOccurrencesOfString:@"{{title}}" withString:defaultDate options:0 range:NSMakeRange(0, rendered.length)];

    NSRegularExpression *regex = OMCRegex(@"\\{\\{date:([^}]+)\\}\\}");
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:rendered options:0 range:NSMakeRange(0, rendered.length)];
    for (NSTextCheckingResult *match in matches.reverseObjectEnumerator) {
        NSString *format = [rendered substringWithRange:[match rangeAtIndex:1]];
        NSString *value = OMCDateTemplateString(date, format);
        [rendered replaceCharactersInRange:match.range withString:value];
    }
    return rendered;
}

static NSString *OMCFindDailyTemplatePath(OMCConfig *config) {
    NSString *vaultRoot = OMCVaultRootForConfig(config);
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];

    NSDictionary *templatesConfig = OMCJSONDictionaryAtPath([vaultRoot stringByAppendingPathComponent:@".obsidian/templates.json"]);
    NSString *templatesFolder = [templatesConfig[@"folder"] isKindOfClass:NSString.class] ? templatesConfig[@"folder"] : nil;
    if (templatesFolder.length > 0) {
        NSString *folderPath = [vaultRoot stringByAppendingPathComponent:templatesFolder];
        [candidates addObject:[folderPath stringByAppendingPathComponent:@"日记模板.md"]];
        [candidates addObject:[folderPath stringByAppendingPathComponent:@"每日模板.md"]];
        [candidates addObject:[folderPath stringByAppendingPathComponent:@"Daily Note.md"]];
    }

    [candidates addObject:[vaultRoot stringByAppendingPathComponent:@"00-Asset/日记模板.md"]];
    [candidates addObject:[vaultRoot stringByAppendingPathComponent:@"00-模板文件/日记模板.md"]];

    for (NSString *candidate in candidates) {
        BOOL isDirectory = NO;
        if ([fileManager fileExistsAtPath:candidate isDirectory:&isDirectory] && !isDirectory) {
            return candidate;
        }
    }

    NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:[NSURL fileURLWithPath:vaultRoot]
                                                   includingPropertiesForKeys:nil
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                 errorHandler:nil];
    NSString *fallback = nil;
    for (NSURL *url in enumerator) {
        if (![url.pathExtension.lowercaseString isEqualToString:@"md"]) {
            continue;
        }
        NSString *name = url.lastPathComponent;
        if ([name isEqualToString:@"日记模板.md"]) {
            return url.path;
        }
        if (!fallback && [name containsString:@"日记"] && [name containsString:@"模板"]) {
            fallback = url.path;
        }
    }
    return fallback;
}

static OMCTextFile *OMCCreateTextFileFromTemplate(OMCConfig *config, NSDate *date, NSError **error) {
    NSString *templatePath = OMCFindDailyTemplatePath(config);
    NSString *templateText = nil;
    if (templatePath.length > 0) {
        templateText = [NSString stringWithContentsOfFile:templatePath encoding:NSUTF8StringEncoding error:nil];
    }
    if (templateText.length == 0) {
        templateText = @"---\n锻炼:\n英语:\n补剂:\n手机:\n---\n# {{date}}\n### 今日任务\n\n\n### 今日感悟\n";
    }
    return OMCTextFileFromString(OMCRenderDailyTemplate(templateText, date));
}

static NSArray<NSDate *> *OMCDatesForVisibleMonth(NSDate *visibleMonth) {
    NSCalendar *calendar = OMCCalendar();
    NSDate *monthStart = nil;
    NSTimeInterval monthDuration = 0;
    if (![calendar rangeOfUnit:NSCalendarUnitMonth startDate:&monthStart interval:&monthDuration forDate:visibleMonth]) {
        return @[];
    }
    NSDate *monthEnd = [monthStart dateByAddingTimeInterval:monthDuration];
    NSDate *lastDay = [calendar dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:monthEnd options:0];

    NSDate *gridStart = nil;
    NSTimeInterval ignored = 0;
    [calendar rangeOfUnit:NSCalendarUnitWeekOfMonth startDate:&gridStart interval:&ignored forDate:monthStart];

    NSDate *lastWeekStart = nil;
    NSTimeInterval lastWeekDuration = 0;
    [calendar rangeOfUnit:NSCalendarUnitWeekOfMonth startDate:&lastWeekStart interval:&lastWeekDuration forDate:lastDay];
    NSDate *gridEnd = [lastWeekStart dateByAddingTimeInterval:lastWeekDuration];

    NSMutableArray<NSDate *> *dates = [NSMutableArray array];
    NSDate *cursor = OMCStartOfDay(gridStart);
    NSDate *end = OMCStartOfDay(gridEnd);
    while ([cursor compare:end] == NSOrderedAscending) {
        [dates addObject:cursor];
        cursor = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:cursor options:0];
    }
    while (dates.count < 42) {
        NSDate *last = dates.lastObject ?: cursor;
        [dates addObject:[calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:last options:0]];
    }
    if (dates.count > 42) {
        return [dates subarrayWithRange:NSMakeRange(0, 42)];
    }
    return dates;
}

static NSArray<OMCTask *> *OMCLoadTasksForDate(OMCConfig *config, NSDate *date, NSMutableSet<NSString *> *watchedPaths, NSError **error) {
    NSString *path = OMCNotePathForDate(config, date);
    [watchedPaths addObject:path];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        return @[];
    }

    OMCTextFile *file = OMCReadTextFile(path, error);
    if (!file) {
        return @[];
    }

    NSMutableArray<OMCTask *> *tasks = [NSMutableArray array];
    [file.lines enumerateObjectsUsingBlock:^(NSString *line, NSUInteger index, BOOL *stop) {
        OMCTask *task = OMCParseTaskLine(line, (NSInteger)index, path, date);
        if (task) {
            [tasks addObject:task];
        }
    }];
    return tasks;
}

static NSArray<OMCTask *> *OMCLoadDatedTasksFromFile(NSString *path, NSMutableSet<NSString *> *watchedPaths, NSError **error) {
    [watchedPaths addObject:path];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        return @[];
    }

    OMCTextFile *file = OMCReadTextFile(path, error);
    if (!file) {
        return @[];
    }

    NSMutableArray<OMCTask *> *tasks = [NSMutableArray array];
    [file.lines enumerateObjectsUsingBlock:^(NSString *line, NSUInteger index, BOOL *stop) {
        NSString *body = OMCFirstCapture(line, OMCCheckboxPattern(), 4);
        NSDate *dueDate = OMCDateFromDueDateInText(body ?: line);
        if (!dueDate) {
            return;
        }

        OMCTask *task = OMCParseTaskLine(line, (NSInteger)index, path, dueDate);
        if (task) {
            [tasks addObject:task];
        }
    }];
    return tasks;
}

static NSArray<NSString *> *OMCExtraTaskSourcePaths(OMCConfig *config) {
    NSString *raw = config.dailyFolder ?: @"";
    NSCharacterSet *separatorSet = [NSCharacterSet characterSetWithCharactersInString:@",，;；\n"];
    NSArray<NSString *> *parts = [raw componentsSeparatedByCharactersInSet:separatorSet];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSString *base = config.dailyNotesPath;

    for (NSString *part in parts) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) {
            continue;
        }

        NSString *path = trimmed.stringByExpandingTildeInPath;
        if (!path.isAbsolutePath) {
            path = [base stringByAppendingPathComponent:trimmed];
        }
        path = path.stringByStandardizingPath;
        if (![seen containsObject:path]) {
            [seen addObject:path];
            [paths addObject:path];
        }
    }
    return paths;
}

static BOOL OMCPathIsDailyNoteForTask(OMCConfig *config, OMCTask *task) {
    NSString *dailyPath = [OMCNotePathForDate(config, task.date) stringByStandardizingPath];
    NSString *taskPath = [task.filePath stringByStandardizingPath];
    return [dailyPath isEqualToString:taskPath];
}

static NSInteger OMCLocateTask(OMCTask *task, NSArray<NSString *> *lines) {
    NSString *storedIdentity = OMCStableIdentityFromTaskLine(task.rawLine);
    if (!storedIdentity) {
        return NSNotFound;
    }
    if (task.lineIndex >= 0 && task.lineIndex < (NSInteger)lines.count) {
        NSString *candidate = OMCStableIdentityFromTaskLine(lines[(NSUInteger)task.lineIndex]);
        if ([candidate isEqualToString:storedIdentity]) {
            return task.lineIndex;
        }
    }

    NSMutableArray<NSNumber *> *matches = [NSMutableArray array];
    [lines enumerateObjectsUsingBlock:^(NSString *line, NSUInteger index, BOOL *stop) {
        NSString *identity = OMCStableIdentityFromTaskLine(line);
        if ([identity isEqualToString:storedIdentity]) {
            [matches addObject:@(index)];
        }
    }];
    return matches.count == 1 ? matches.firstObject.integerValue : NSNotFound;
}

static BOOL OMCSetTaskDone(OMCTask *task, BOOL done, NSDate *completionDate, NSError **error) {
    if (![NSFileManager.defaultManager fileExistsAtPath:task.filePath]) {
        if (error) {
            *error = [NSError errorWithDomain:@"ObsidianMenuCalendar" code:1 userInfo:@{NSLocalizedDescriptionKey: @"无法读取或写入目标文件。"}];
        }
        return NO;
    }

    OMCTextFile *file = OMCReadTextFile(task.filePath, error);
    if (!file) {
        return NO;
    }

    NSInteger index = OMCLocateTask(task, file.lines);
    if (index == NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:@"ObsidianMenuCalendar" code:2 userInfo:@{NSLocalizedDescriptionKey: @"这条任务已经在 Obsidian 中被移动或修改，已刷新列表，没有覆盖你的新内容。"}];
        }
        return NO;
    }

    NSString *updated = OMCLineByReplacingCompletionState(file.lines[(NSUInteger)index], done, completionDate);
    if (!updated) {
        if (error) {
            *error = [NSError errorWithDomain:@"ObsidianMenuCalendar" code:3 userInfo:@{NSLocalizedDescriptionKey: @"目标行已经不再是任务，已刷新列表。"}];
        }
        return NO;
    }

    file.lines[(NSUInteger)index] = updated;
    NSString *rendered = OMCRenderTextFile(file);
    return [rendered writeToFile:task.filePath atomically:YES encoding:NSUTF8StringEncoding error:error];
}

static BOOL OMCUpdateTaskText(OMCTask *task, NSString *newText, NSError **error) {
    if (![NSFileManager.defaultManager fileExistsAtPath:task.filePath]) {
        if (error) {
            *error = [NSError errorWithDomain:@"ObsidianMenuCalendar" code:8 userInfo:@{NSLocalizedDescriptionKey: @"无法读取或写入目标文件。"}];
        }
        return NO;
    }

    OMCTextFile *file = OMCReadTextFile(task.filePath, error);
    if (!file) {
        return NO;
    }

    NSInteger index = OMCLocateTask(task, file.lines);
    if (index == NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:@"ObsidianMenuCalendar" code:9 userInfo:@{NSLocalizedDescriptionKey: @"这条任务已经在 Obsidian 中被移动或修改，已刷新列表，没有覆盖你的新内容。"}];
        }
        return NO;
    }

    NSString *updated = OMCLineByReplacingTaskText(file.lines[(NSUInteger)index], newText);
    if (!updated) {
        if (error) {
            *error = [NSError errorWithDomain:@"ObsidianMenuCalendar" code:10 userInfo:@{NSLocalizedDescriptionKey: @"任务内容不能为空，或者目标行已经不再是任务。"}];
        }
        return NO;
    }

    file.lines[(NSUInteger)index] = updated;
    return [OMCRenderTextFile(file) writeToFile:task.filePath atomically:YES encoding:NSUTF8StringEncoding error:error];
}

static BOOL OMCDeleteTask(OMCTask *task, NSError **error) {
    if (![NSFileManager.defaultManager fileExistsAtPath:task.filePath]) {
        if (error) {
            *error = [NSError errorWithDomain:@"ObsidianMenuCalendar" code:11 userInfo:@{NSLocalizedDescriptionKey: @"无法读取或写入目标文件。"}];
        }
        return NO;
    }

    OMCTextFile *file = OMCReadTextFile(task.filePath, error);
    if (!file) {
        return NO;
    }

    NSInteger index = OMCLocateTask(task, file.lines);
    if (index == NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:@"ObsidianMenuCalendar" code:12 userInfo:@{NSLocalizedDescriptionKey: @"这条任务已经在 Obsidian 中被移动或修改，已刷新列表，没有覆盖你的新内容。"}];
        }
        return NO;
    }

    [file.lines removeObjectAtIndex:(NSUInteger)index];
    return [OMCRenderTextFile(file) writeToFile:task.filePath atomically:YES encoding:NSUTF8StringEncoding error:error];
}

static BOOL OMCMoveTaskToDate(OMCConfig *config, OMCTask *task, NSDate *targetDate, NSError **error) {
    NSDate *targetDay = OMCStartOfDay(targetDate);
    if (!task || !targetDay) {
        if (error) {
            *error = [NSError errorWithDomain:@"ObsidianMenuCalendar" code:14 userInfo:@{NSLocalizedDescriptionKey: @"没有找到要移动的任务。"}];
        }
        return NO;
    }
    if ([OMCCalendar() isDate:task.date inSameDayAsDate:targetDay]) {
        return YES;
    }
    if (![NSFileManager.defaultManager fileExistsAtPath:task.filePath]) {
        if (error) {
            *error = [NSError errorWithDomain:@"ObsidianMenuCalendar" code:15 userInfo:@{NSLocalizedDescriptionKey: @"无法读取或写入目标文件。"}];
        }
        return NO;
    }

    OMCTextFile *sourceFile = OMCReadTextFile(task.filePath, error);
    if (!sourceFile) {
        return NO;
    }

    NSInteger index = OMCLocateTask(task, sourceFile.lines);
    if (index == NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:@"ObsidianMenuCalendar" code:16 userInfo:@{NSLocalizedDescriptionKey: @"这条任务已经在 Obsidian 中被移动或修改，已刷新列表，没有覆盖你的新内容。"}];
        }
        return NO;
    }

    NSString *updatedLine = OMCLineByReplacingDueDate(sourceFile.lines[(NSUInteger)index], targetDay);
    if (!updatedLine) {
        if (error) {
            *error = [NSError errorWithDomain:@"ObsidianMenuCalendar" code:17 userInfo:@{NSLocalizedDescriptionKey: @"目标行已经不再是任务，无法移动。"}];
        }
        return NO;
    }

    if (OMCPathIsDailyNoteForTask(config, task)) {
        NSString *targetPath = [OMCNotePathForDate(config, targetDay) stringByStandardizingPath];
        NSString *sourcePath = [task.filePath stringByStandardizingPath];
        if ([targetPath isEqualToString:sourcePath]) {
            sourceFile.lines[(NSUInteger)index] = updatedLine;
            return [OMCRenderTextFile(sourceFile) writeToFile:task.filePath atomically:YES encoding:NSUTF8StringEncoding error:error];
        }

        if (!OMCAppendTaskLineToDailyNote(config, targetDay, updatedLine, error)) {
            return NO;
        }
        [sourceFile.lines removeObjectAtIndex:(NSUInteger)index];
        return [OMCRenderTextFile(sourceFile) writeToFile:task.filePath atomically:YES encoding:NSUTF8StringEncoding error:error];
    }

    sourceFile.lines[(NSUInteger)index] = updatedLine;
    return [OMCRenderTextFile(sourceFile) writeToFile:task.filePath atomically:YES encoding:NSUTF8StringEncoding error:error];
}

static NSArray<OMCTask *> *OMCSortedTasks(NSArray<OMCTask *> *tasks) {
    return [tasks sortedArrayUsingComparator:^NSComparisonResult(OMCTask *a, OMCTask *b) {
        if (a.done != b.done) {
            return a.done ? NSOrderedDescending : NSOrderedAscending;
        }
        NSString *left = a.timeText ?: @"99:99";
        NSString *right = b.timeText ?: @"99:99";
        NSComparisonResult timeResult = [left compare:right];
        if (timeResult != NSOrderedSame) return timeResult;
        return [a.title compare:b.title];
    }];
}

@class OMCAppDelegate;
@class OMCDayCell;

@protocol OMCDayCellDropDelegate <NSObject>
- (BOOL)dayCell:(OMCDayCell *)cell acceptDraggedTaskIdentifier:(NSString *)identifier;
@end

@interface OMCDayCell : NSControl
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, strong) NSDate *visibleMonth;
@property (nonatomic, strong) NSDate *selectedDate;
@property (nonatomic, copy) NSArray<OMCTask *> *tasks;
@property (nonatomic, weak) id<OMCDayCellDropDelegate> dropDelegate;
@property (nonatomic, assign) BOOL dragHighlighted;
@property (nonatomic, assign) NSInteger dotThresholdOne;
@property (nonatomic, assign) NSInteger dotThresholdTwo;
@property (nonatomic, assign) NSInteger dotThresholdThree;
@end

@implementation OMCDayCell
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self registerForDraggedTypes:@[OMCDraggedTaskPasteboardType]];
    }
    return self;
}
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSCalendar *calendar = OMCCalendar();
    BOOL isSelected = [calendar isDate:self.date inSameDayAsDate:self.selectedDate];
    BOOL isToday = [calendar isDateInToday:self.date];
    BOOL isInMonth = [calendar isDate:self.date equalToDate:self.visibleMonth toUnitGranularity:NSCalendarUnitMonth];

    CGFloat markerSize = 29;
    NSRect insetBounds = NSMakeRect((self.bounds.size.width - markerSize) / 2, 1, markerSize, markerSize);
    if (self.dragHighlighted) {
        [[OMCTaskTintColor() colorWithAlphaComponent:0.16] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 2, 1) xRadius:9 yRadius:9] fill];
        [[OMCTaskTintColor() colorWithAlphaComponent:0.62] setStroke];
        NSBezierPath *dropPath = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 2.5, 1.5) xRadius:9 yRadius:9];
        dropPath.lineWidth = 1.2;
        [dropPath stroke];
    }

    if (isToday) {
        [OMCAccentColor() setFill];
        [[NSBezierPath bezierPathWithRoundedRect:insetBounds xRadius:8 yRadius:8] fill];
    } else if (isSelected) {
        [OMCAccentSoftColor() setFill];
        [[NSBezierPath bezierPathWithRoundedRect:insetBounds xRadius:8 yRadius:8] fill];
        [OMCAccentColor() setStroke];
        NSBezierPath *strokePath = [NSBezierPath bezierPathWithRoundedRect:insetBounds xRadius:8 yRadius:8];
        strokePath.lineWidth = 1;
        [strokePath stroke];
    }

    NSColor *dayColor = OMCTextColor();
    if (isToday) dayColor = NSColor.whiteColor;
    else if (!isInMonth) dayColor = [OMCSecondaryTextColor() colorWithAlphaComponent:0.38];

    NSInteger day = [calendar component:NSCalendarUnitDay fromDate:self.date];
    NSString *dayText = [NSString stringWithFormat:@"%ld", (long)day];
    NSDictionary *dayAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14 weight:(isToday || isSelected) ? NSFontWeightBold : NSFontWeightSemibold],
        NSForegroundColorAttributeName: dayColor
    };
    NSSize daySize = [dayText sizeWithAttributes:dayAttrs];
    [dayText drawAtPoint:NSMakePoint((self.bounds.size.width - daySize.width) / 2, 1) withAttributes:dayAttrs];

    NSString *specialText = OMCSpecialDayText(self.date);
    NSString *subtitleText = specialText.length > 0 ? specialText : OMCLunarDayText(self.date);
    NSColor *subtitleColor = isToday ? [NSColor.whiteColor colorWithAlphaComponent:0.86] : (isInMonth ? [OMCSecondaryTextColor() colorWithAlphaComponent:0.88] : [OMCSecondaryTextColor() colorWithAlphaComponent:0.34]);
    if (specialText.length > 0 && isInMonth && !isToday) {
        subtitleColor = [OMCAccentColor() colorWithAlphaComponent:isSelected ? 0.88 : 0.78];
    }
    NSDictionary *subtitleAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:9.5 weight:specialText.length > 0 ? NSFontWeightSemibold : NSFontWeightMedium],
        NSForegroundColorAttributeName: subtitleColor
    };
    NSSize subtitleSize = [subtitleText sizeWithAttributes:subtitleAttrs];
    [subtitleText drawAtPoint:NSMakePoint((self.bounds.size.width - subtitleSize.width) / 2, 17) withAttributes:subtitleAttrs];

    CGFloat dotSize = 4.0;
    CGFloat spacing = 3.5;
    NSUInteger taskCount = self.tasks.count;
    NSUInteger dotCount = 0;
    NSInteger thresholdOne = self.dotThresholdOne > 0 ? self.dotThresholdOne : 1;
    NSInteger thresholdTwo = self.dotThresholdTwo > thresholdOne ? self.dotThresholdTwo : thresholdOne + 1;
    NSInteger thresholdThree = self.dotThresholdThree > thresholdTwo ? self.dotThresholdThree : thresholdTwo + 1;
    if (taskCount >= (NSUInteger)thresholdThree) {
        dotCount = 3;
    } else if (taskCount >= (NSUInteger)thresholdTwo) {
        dotCount = 2;
    } else if (taskCount >= (NSUInteger)thresholdOne) {
        dotCount = 1;
    }
    CGFloat totalWidth = dotCount == 0 ? 0 : dotCount * dotSize + (dotCount - 1) * spacing;
    CGFloat startX = (self.bounds.size.width - totalWidth) / 2;
    for (NSUInteger i = 0; i < dotCount; i++) {
        NSColor *color = i < self.tasks.count ? OMCColorForTask(self.tasks[i]) : NSColor.systemGrayColor;
        if (self.tasks[i].done) {
            color = [color colorWithAlphaComponent:0.35];
        }
        [color setFill];
        NSRect dotRect = NSMakeRect(startX + i * (dotSize + spacing), 32, dotSize, dotSize);
        [[NSBezierPath bezierPathWithOvalInRect:dotRect] fill];
    }
}
- (void)mouseDown:(NSEvent *)event {
    [self sendAction:self.action to:self.target];
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    NSString *identifier = [sender.draggingPasteboard stringForType:OMCDraggedTaskPasteboardType];
    if (identifier.length == 0) {
        return NSDragOperationNone;
    }
    self.dragHighlighted = YES;
    self.needsDisplay = YES;
    return NSDragOperationMove;
}
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    return [sender.draggingPasteboard stringForType:OMCDraggedTaskPasteboardType].length > 0 ? NSDragOperationMove : NSDragOperationNone;
}
- (void)draggingExited:(id<NSDraggingInfo>)sender {
    self.dragHighlighted = NO;
    self.needsDisplay = YES;
}
- (void)draggingEnded:(id<NSDraggingInfo>)sender {
    self.dragHighlighted = NO;
    self.needsDisplay = YES;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSString *identifier = [sender.draggingPasteboard stringForType:OMCDraggedTaskPasteboardType];
    self.dragHighlighted = NO;
    self.needsDisplay = YES;
    if (identifier.length == 0) {
        return NO;
    }
    return [self.dropDelegate dayCell:self acceptDraggedTaskIdentifier:identifier];
}
@end

@interface OMCTaskDragView : NSView <NSDraggingSource>
@property (nonatomic, strong) OMCTask *task;
@end

@implementation OMCTaskDragView {
    NSPoint _mouseDownPoint;
    BOOL _dragging;
}
- (BOOL)isFlipped { return YES; }
- (void)mouseDown:(NSEvent *)event {
    _mouseDownPoint = [self convertPoint:event.locationInWindow fromView:nil];
    _dragging = NO;
}
- (void)mouseDragged:(NSEvent *)event {
    if (_dragging || self.task.identifier.length == 0) {
        return;
    }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat dx = point.x - _mouseDownPoint.x;
    CGFloat dy = point.y - _mouseDownPoint.y;
    if (sqrt(dx * dx + dy * dy) < 4.0) {
        return;
    }
    _dragging = YES;

    NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
    [item setString:self.task.identifier forType:OMCDraggedTaskPasteboardType];

    NSString *title = self.task.title.length > 0 ? self.task.title : @"任务";
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(170, 36)];
    [image lockFocus];
    [[NSColor colorWithCalibratedWhite:1 alpha:0.94] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, 170, 36) xRadius:8 yRadius:8] fill];
    [[OMCTaskTintColor() colorWithAlphaComponent:0.92] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(9, 8, 4, 20) xRadius:2 yRadius:2] fill];
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: OMCTextColor()
    };
    [title drawInRect:NSMakeRect(22, 9, 138, 18) withAttributes:attrs];
    [image unlockFocus];

    NSDraggingItem *draggingItem = [[NSDraggingItem alloc] initWithPasteboardWriter:item];
    [draggingItem setDraggingFrame:NSMakeRect(point.x - 18, point.y - 18, 170, 36) contents:image];
    [self beginDraggingSessionWithItems:@[draggingItem] event:event source:self];
}
- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    return NSDragOperationMove;
}
@end

@interface OMCTaskButton : NSButton
@property (nonatomic, strong) OMCTask *task;
@property (nonatomic, strong) NSColor *overrideColor;
@end

@implementation OMCTaskButton
- (BOOL)isFlipped { return YES; }
- (void)setTask:(OMCTask *)task {
    _task = task;
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    NSColor *taskColor = self.overrideColor ?: OMCColorForTask(self.task);
    CGFloat side = MIN(self.bounds.size.width, self.bounds.size.height) - 5;
    NSRect box = NSMakeRect((self.bounds.size.width - side) / 2, (self.bounds.size.height - side) / 2, side, side);
    NSBezierPath *boxPath = [NSBezierPath bezierPathWithRoundedRect:box xRadius:4 yRadius:4];
    boxPath.lineWidth = 1.35;

    if (self.task.done) {
        [[taskColor colorWithAlphaComponent:0.88] setFill];
        [boxPath fill];
        [[taskColor colorWithAlphaComponent:0.95] setStroke];
        [boxPath stroke];

        NSBezierPath *checkPath = [NSBezierPath bezierPath];
        CGFloat minX = NSMinX(box);
        CGFloat minY = NSMinY(box);
        [checkPath moveToPoint:NSMakePoint(minX + side * 0.24, minY + side * 0.54)];
        [checkPath lineToPoint:NSMakePoint(minX + side * 0.43, minY + side * 0.71)];
        [checkPath lineToPoint:NSMakePoint(minX + side * 0.76, minY + side * 0.31)];
        checkPath.lineWidth = 1.9;
        checkPath.lineCapStyle = NSLineCapStyleRound;
        checkPath.lineJoinStyle = NSLineJoinStyleRound;
        [NSColor.whiteColor setStroke];
        [checkPath stroke];
    } else {
        [[NSColor colorWithWhite:1 alpha:0.72] setFill];
        [boxPath fill];
        [[taskColor colorWithAlphaComponent:0.72] setStroke];
        [boxPath stroke];
    }
}
@end

@interface OMCDayButton : OMCDayCell
@end

@implementation OMCDayButton
@end

@interface OMCAppDelegate : NSObject <NSApplicationDelegate, NSTextFieldDelegate, OMCDayCellDropDelegate>
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) OMCInputPanel *calendarPanel;
@property (nonatomic, strong) NSViewController *viewController;
@property (nonatomic, strong) OMCConfig *config;
@property (nonatomic, strong) NSDate *selectedDate;
@property (nonatomic, strong) NSDate *visibleMonth;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<OMCTask *> *> *tasksByDate;
@property (nonatomic, strong) NSMutableDictionary<NSString *, OMCTaskCacheEntry *> *taskCache;
@property (nonatomic, strong) NSMutableArray *watchSources;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *watchFDs;
@property (nonatomic, copy) NSSet<NSString *> *watchedPathSet;
@property (nonatomic, copy) NSString *errorMessage;
@property (nonatomic, assign) BOOL showingSettings;
@property (nonatomic, strong) NSTextField *vaultField;
@property (nonatomic, strong) NSTextField *folderField;
@property (nonatomic, strong) NSTextField *formatField;
@property (nonatomic, strong) NSTextField *lookAheadField;
@property (nonatomic, strong) NSColorWell *accentColorWell;
@property (nonatomic, strong) NSTextField *dotOneField;
@property (nonatomic, strong) NSTextField *dotTwoField;
@property (nonatomic, strong) NSTextField *dotThreeField;
@property (nonatomic, strong) NSButton *launchAtLoginButton;
@property (nonatomic, strong) NSPanel *addTaskPanel;
@property (nonatomic, strong) NSTextField *addTaskInput;
@property (nonatomic, strong) NSTextField *inlineTaskInput;
@property (nonatomic, copy) NSString *inlineDraftText;
@property (nonatomic, assign) BOOL inlineInputActive;
@property (nonatomic, strong) id outsideClickMonitor;
@property (nonatomic, strong) id keyboardMonitor;
@property (nonatomic, assign) BOOL allowingPopoverClose;
@property (nonatomic, assign) BOOL dataLoaded;
@property (nonatomic, assign) BOOL dataDirty;
@property (nonatomic, copy) NSString *loadedDayKey;
@end

@implementation OMCAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.config = OMCLoadConfig();
    self.selectedDate = OMCStartOfDay([NSDate date]);
    self.visibleMonth = [self monthStartForDate:self.selectedDate];
    self.tasksByDate = [NSMutableDictionary dictionary];
    self.taskCache = [NSMutableDictionary dictionary];
    self.watchSources = [NSMutableArray array];
    self.watchFDs = [NSMutableArray array];
    self.showingSettings = !self.config.hasVault;
    self.dataDirty = YES;

    [self setupStatusItem];
    [self setupPopover];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(applicationDidResignActive:)
                                               name:NSApplicationDidResignActiveNotification
                                             object:NSApp];
    [self reloadDataAndRender];
}

- (void)setupStatusItem {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    NSStatusBarButton *button = self.statusItem.button;
    button.image = [NSImage imageWithSystemSymbolName:@"calendar" accessibilityDescription:@"Obsidian daily tasks"];
    button.title = @"0";
    button.target = self;
    button.action = @selector(togglePopover:);
}

- (void)setupPopover {
    self.viewController = [[NSViewController alloc] init];
    self.calendarPanel = [[OMCInputPanel alloc] initWithContentRect:NSMakeRect(0, 0, OMCWidth, OMCHeight)
                                                          styleMask:NSWindowStyleMaskBorderless
                                                            backing:NSBackingStoreBuffered
                                                              defer:NO];
    self.calendarPanel.opaque = NO;
    self.calendarPanel.backgroundColor = NSColor.clearColor;
    self.calendarPanel.hasShadow = YES;
    self.calendarPanel.level = NSStatusWindowLevel;
    self.calendarPanel.hidesOnDeactivate = NO;
    self.calendarPanel.releasedWhenClosed = NO;
    self.calendarPanel.movable = NO;
    self.calendarPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
}

- (void)togglePopover:(id)sender {
    if (self.calendarPanel.isVisible) {
        NSEvent *event = NSApp.currentEvent;
        if (event.type == NSEventTypeKeyDown) {
            [self focusInlineTaskInput];
            return;
        }
        [self closePopover];
        return;
    }
    NSString *todayKey = OMCCanonicalDateKey([NSDate date]);
    if (!self.dataLoaded || self.dataDirty || ![self.loadedDayKey isEqualToString:todayKey]) {
        [self reloadDataAndRender];
    } else {
        [self renderPopoverContent];
    }
    [self positionCalendarPanel];
    [NSApp activateIgnoringOtherApps:YES];
    [self.calendarPanel makeKeyAndOrderFront:nil];
    [self installOutsideClickMonitor];
    [self installKeyboardMonitor];
}

- (void)applicationDidResignActive:(NSNotification *)notification {
    if (self.addTaskPanel) {
        [self.addTaskPanel close];
        self.addTaskPanel = nil;
        self.addTaskInput = nil;
    }
    if (self.calendarPanel.isVisible && NSApp.modalWindow == nil) {
        if (self.inlineInputActive) {
            return;
        }
        [self closePopover];
    }
}

- (void)positionCalendarPanel {
    NSStatusBarButton *button = self.statusItem.button;
    NSWindow *buttonWindow = button.window;
    NSScreen *screen = buttonWindow.screen ?: NSScreen.mainScreen;
    NSRect visibleFrame = screen.visibleFrame;
    NSRect buttonRect = buttonWindow ? [buttonWindow convertRectToScreen:[button convertRect:button.bounds toView:nil]] : NSMakeRect(NSMaxX(visibleFrame) - 80, NSMaxY(visibleFrame), 44, 22);

    CGFloat x = NSMaxX(buttonRect) - OMCWidth + 18;
    CGFloat y = NSMinY(buttonRect) - OMCHeight - 8;
    if (y < NSMinY(visibleFrame) + 8) {
        y = NSMinY(visibleFrame) + 8;
    }
    x = MAX(NSMinX(visibleFrame) + 8, MIN(x, NSMaxX(visibleFrame) - OMCWidth - 8));
    [self.calendarPanel setFrame:NSMakeRect(x, y, OMCWidth, OMCHeight) display:NO];
}

- (void)installOutsideClickMonitor {
    if (self.outsideClickMonitor) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    self.outsideClickMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown
                                                                      handler:^(NSEvent *event) {
        dispatch_async(dispatch_get_main_queue(), ^{
            OMCAppDelegate *strongSelf = weakSelf;
            if (strongSelf.calendarPanel.isVisible) {
                [strongSelf closePopover];
            }
        });
    }];
}

- (void)removeOutsideClickMonitor {
    if (!self.outsideClickMonitor) {
        return;
    }
    [NSEvent removeMonitor:self.outsideClickMonitor];
    self.outsideClickMonitor = nil;
}

- (void)installKeyboardMonitor {
    if (self.keyboardMonitor) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    self.keyboardMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        OMCAppDelegate *strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.calendarPanel.isVisible) {
            return event;
        }

        NSWindow *window = strongSelf.calendarPanel;
        BOOL commandDown = (event.modifierFlags & NSEventModifierFlagCommand) == NSEventModifierFlagCommand;
        if (commandDown && [window.firstResponder isKindOfClass:NSTextView.class]) {
            NSTextView *textView = (NSTextView *)window.firstResponder;
            NSString *key = event.charactersIgnoringModifiers.lowercaseString ?: @"";
            if ([key isEqualToString:@"v"]) {
                [textView paste:nil];
                return nil;
            }
            if ([key isEqualToString:@"c"]) {
                [textView copy:nil];
                return nil;
            }
            if ([key isEqualToString:@"x"]) {
                [textView cut:nil];
                return nil;
            }
            if ([key isEqualToString:@"a"]) {
                [textView selectAll:nil];
                return nil;
            }
            if ([key isEqualToString:@"z"]) {
                if ((event.modifierFlags & NSEventModifierFlagShift) == NSEventModifierFlagShift) {
                    [textView.undoManager redo];
                } else {
                    [textView.undoManager undo];
                }
                return nil;
            }
        }

        BOOL isSpace = event.keyCode == 49;
        BOOL isReturn = event.keyCode == 36 || event.keyCode == 76;
        if (!isSpace && !isReturn) {
            return event;
        }

        if (!strongSelf.inlineInputActive) {
            return nil;
        }

        id fieldEditor = [window fieldEditor:NO forObject:strongSelf.inlineTaskInput];
        BOOL inputHasFocus = fieldEditor && window.firstResponder == fieldEditor;
        if (inputHasFocus) {
            return event;
        }

        [strongSelf focusInlineTaskInput];
        if (isReturn) {
            NSString *taskText = [strongSelf.inlineTaskInput.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (taskText.length > 0) {
                [strongSelf confirmInlineTaskInput:strongSelf.inlineTaskInput];
            }
        }
        return nil;
    }];
}

- (void)removeKeyboardMonitor {
    if (!self.keyboardMonitor) {
        return;
    }
    [NSEvent removeMonitor:self.keyboardMonitor];
    self.keyboardMonitor = nil;
}

- (void)closePopover {
    [self removeOutsideClickMonitor];
    [self removeKeyboardMonitor];
    self.inlineInputActive = NO;
    self.allowingPopoverClose = YES;
    [self.calendarPanel orderOut:nil];
    self.allowingPopoverClose = NO;
}

- (NSDate *)monthStartForDate:(NSDate *)date {
    NSDate *start = nil;
    NSTimeInterval interval = 0;
    [OMCCalendar() rangeOfUnit:NSCalendarUnitMonth startDate:&start interval:&interval forDate:date];
    return start ?: OMCStartOfDay(date);
}

- (NSArray<OMCTask *> *)tasksForDate:(NSDate *)date {
    return self.tasksByDate[OMCCanonicalDateKey(date)] ?: @[];
}

- (NSArray<OMCTask *> *)upcomingTasks {
    NSMutableArray<OMCTask *> *tasks = [NSMutableArray array];
    NSDate *today = OMCStartOfDay([NSDate date]);
    NSDate *start = [OMCCalendar() dateByAddingUnit:NSCalendarUnitDay value:1 toDate:today options:0];
    NSDate *end = [OMCCalendar() dateByAddingUnit:NSCalendarUnitDay value:self.config.lookAheadDays toDate:today options:0];
    for (NSString *key in self.tasksByDate) {
        NSDate *date = [OMCDateFormatter(@"yyyy-MM-dd") dateFromString:key];
        if ([date compare:start] != NSOrderedAscending && [date compare:end] != NSOrderedDescending) {
            [tasks addObjectsFromArray:self.tasksByDate[key]];
        }
    }
    return [tasks sortedArrayUsingComparator:^NSComparisonResult(OMCTask *a, OMCTask *b) {
        NSComparisonResult dateResult = [a.date compare:b.date];
        if (dateResult != NSOrderedSame) return dateResult;
        NSString *left = a.timeText ?: @"99:99";
        NSString *right = b.timeText ?: @"99:99";
        NSComparisonResult timeResult = [left compare:right];
        if (timeResult != NSOrderedSame) return timeResult;
        return [a.title compare:b.title];
    }];
}

- (NSArray<OMCTask *> *)tasksForDate:(NSDate *)date done:(BOOL)done {
    NSMutableArray<OMCTask *> *filtered = [NSMutableArray array];
    for (OMCTask *task in [self tasksForDate:date]) {
        if (task.done == done) {
            [filtered addObject:task];
        }
    }
    return filtered;
}

- (NSArray<OMCTask *> *)overdueTasks {
    NSMutableArray<OMCTask *> *tasks = [NSMutableArray array];
    NSDate *today = OMCStartOfDay([NSDate date]);
    for (NSString *key in self.tasksByDate) {
        NSDate *date = [OMCDateFormatter(@"yyyy-MM-dd") dateFromString:key];
        if (!date || [date compare:today] != NSOrderedAscending) {
            continue;
        }
        for (OMCTask *task in self.tasksByDate[key]) {
            if (!task.done) {
                [tasks addObject:task];
            }
        }
    }
    return [tasks sortedArrayUsingComparator:^NSComparisonResult(OMCTask *a, OMCTask *b) {
        NSComparisonResult dateResult = [b.date compare:a.date];
        if (dateResult != NSOrderedSame) return dateResult;
        NSString *left = a.timeText ?: @"99:99";
        NSString *right = b.timeText ?: @"99:99";
        NSComparisonResult timeResult = [left compare:right];
        if (timeResult != NSOrderedSame) return timeResult;
        return [a.title compare:b.title];
    }];
}

- (void)updateStatusItemTitle {
    NSArray<OMCTask *> *todayTasks = self.tasksByDate[OMCCanonicalDateKey([NSDate date])] ?: @[];
    NSInteger openCount = 0;
    for (OMCTask *task in todayTasks) {
        if (!task.done) {
            openCount += 1;
        }
    }
    self.statusItem.button.title = openCount > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)openCount];
}

- (NSArray<OMCTask *> *)cachedTasksForDate:(NSDate *)date watchPaths:(NSMutableSet<NSString *> *)watchPaths error:(NSError **)error {
    NSString *path = OMCNotePathForDate(self.config, date);
    if (path.length > 0) {
        [watchPaths addObject:path];
    }

    BOOL isDirectory = NO;
    BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] && !isDirectory;
    NSDate *modificationDate = nil;
    if (exists) {
        NSDictionary<NSFileAttributeKey, id> *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
        modificationDate = attributes[NSFileModificationDate];
    }

    NSString *cacheKey = OMCTaskCacheKey(path, date);
    OMCTaskCacheEntry *cached = self.taskCache[cacheKey];
    if (cached && cached.exists == exists && OMCNullableDatesEqual(cached.modificationDate, modificationDate)) {
        return cached.tasks ?: @[];
    }

    NSArray<OMCTask *> *tasks = @[];
    if (exists) {
        NSError *loadError = nil;
        tasks = OMCLoadTasksForDate(self.config, date, watchPaths, &loadError) ?: @[];
        if (loadError) {
            if (error) {
                *error = loadError;
            }
            return tasks;
        }
    }

    OMCTaskCacheEntry *entry = [[OMCTaskCacheEntry alloc] init];
    entry.exists = exists;
    entry.modificationDate = modificationDate;
    entry.tasks = tasks ?: @[];
    self.taskCache[cacheKey] = entry;
    return entry.tasks;
}

- (NSArray<OMCTask *> *)cachedDatedTasksFromFile:(NSString *)path watchPaths:(NSMutableSet<NSString *> *)watchPaths error:(NSError **)error {
    if (path.length > 0) {
        [watchPaths addObject:path];
    }

    BOOL isDirectory = NO;
    BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] && !isDirectory;
    NSDate *modificationDate = nil;
    if (exists) {
        NSDictionary<NSFileAttributeKey, id> *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
        modificationDate = attributes[NSFileModificationDate];
    }

    NSString *cacheKey = [NSString stringWithFormat:@"extra|%@", path ?: @""];
    OMCTaskCacheEntry *cached = self.taskCache[cacheKey];
    if (cached && cached.exists == exists && OMCNullableDatesEqual(cached.modificationDate, modificationDate)) {
        return cached.tasks ?: @[];
    }

    NSArray<OMCTask *> *tasks = @[];
    if (exists) {
        NSError *loadError = nil;
        tasks = OMCLoadDatedTasksFromFile(path, watchPaths, &loadError) ?: @[];
        if (loadError) {
            if (error) {
                *error = loadError;
            }
            return tasks;
        }
    }

    OMCTaskCacheEntry *entry = [[OMCTaskCacheEntry alloc] init];
    entry.exists = exists;
    entry.modificationDate = modificationDate;
    entry.tasks = tasks ?: @[];
    self.taskCache[cacheKey] = entry;
    return entry.tasks;
}

- (NSArray<OMCTask *> *)cachedDailyTasksFromFile:(NSString *)path date:(NSDate *)date watchPaths:(NSMutableSet<NSString *> *)watchPaths error:(NSError **)error {
    if (path.length > 0) {
        [watchPaths addObject:path];
    }

    BOOL isDirectory = NO;
    BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] && !isDirectory;
    NSDate *modificationDate = nil;
    if (exists) {
        NSDictionary<NSFileAttributeKey, id> *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
        modificationDate = attributes[NSFileModificationDate];
    }

    NSString *cacheKey = OMCTaskCacheKey(path, date);
    OMCTaskCacheEntry *cached = self.taskCache[cacheKey];
    if (cached && cached.exists == exists && OMCNullableDatesEqual(cached.modificationDate, modificationDate)) {
        return cached.tasks ?: @[];
    }

    NSArray<OMCTask *> *tasks = @[];
    if (exists) {
        OMCTextFile *file = OMCReadTextFile(path, error);
        if (!file) {
            return @[];
        }

        NSMutableArray<OMCTask *> *parsed = [NSMutableArray array];
        [file.lines enumerateObjectsUsingBlock:^(NSString *line, NSUInteger index, BOOL *stop) {
            OMCTask *task = OMCParseTaskLine(line, (NSInteger)index, path, date);
            if (task) {
                [parsed addObject:task];
            }
        }];
        tasks = parsed;
    }

    OMCTaskCacheEntry *entry = [[OMCTaskCacheEntry alloc] init];
    entry.exists = exists;
    entry.modificationDate = modificationDate;
    entry.tasks = tasks ?: @[];
    self.taskCache[cacheKey] = entry;
    return entry.tasks;
}

- (NSArray<OMCTask *> *)cachedOverdueDailyTasksWithWatchPaths:(NSMutableSet<NSString *> *)watchPaths error:(NSError **)error {
    NSMutableArray<OMCTask *> *tasks = [NSMutableArray array];
    NSString *basePath = self.config.dailyNotesPath.stringByStandardizingPath;
    NSDate *today = OMCStartOfDay([NSDate date]);
    NSDate *earliest = [OMCCalendar() dateByAddingUnit:NSCalendarUnitDay value:-730 toDate:today options:0];
    NSDateFormatter *formatter = OMCDateFormatter(self.config.dateFormat.length > 0 ? self.config.dateFormat : @"yyyy-MM-dd");

    NSDirectoryEnumerator<NSURL *> *enumerator = [NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:basePath]
                                                                    includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                                                       options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                  errorHandler:nil];
    NSUInteger scanned = 0;
    for (NSURL *url in enumerator) {
        scanned += 1;
        if (scanned > 8000) {
            break;
        }

        NSNumber *isDir = nil;
        [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        if (isDir.boolValue) {
            [watchPaths addObject:url.path];
            NSString *name = url.lastPathComponent;
            if ([name isEqualToString:@".obsidian"] || [name isEqualToString:@".trash"] || [name isEqualToString:@"附件"] || [name.lowercaseString isEqualToString:@"attachments"]) {
                [enumerator skipDescendants];
            }
            continue;
        }

        if (![url.pathExtension.lowercaseString isEqualToString:@"md"]) {
            continue;
        }
        NSString *baseName = url.lastPathComponent.stringByDeletingPathExtension;
        NSDate *date = OMCStartOfDay([formatter dateFromString:baseName]);
        if (!date || [date compare:earliest] == NSOrderedAscending || [date compare:today] != NSOrderedAscending) {
            continue;
        }

        NSArray<OMCTask *> *dailyTasks = [self cachedDailyTasksFromFile:url.path date:date watchPaths:watchPaths error:error];
        for (OMCTask *task in dailyTasks) {
            if (!task.done) {
                [tasks addObject:task];
            }
        }
    }
    return tasks;
}

- (NSArray<OMCTask *> *)cachedExtraTasksWithWatchPaths:(NSMutableSet<NSString *> *)watchPaths error:(NSError **)error {
    NSMutableArray<OMCTask *> *tasks = [NSMutableArray array];
    NSArray<NSString *> *sources = OMCExtraTaskSourcePaths(self.config);
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSUInteger scannedFileCount = 0;

    for (NSString *source in sources) {
        BOOL isDirectory = NO;
        if (![fileManager fileExistsAtPath:source isDirectory:&isDirectory]) {
            if (error) {
                *error = [NSError errorWithDomain:@"ObsidianMenuCalendar" code:5 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"额外任务来源不存在：%@", source]}];
            }
            continue;
        }

        [watchPaths addObject:source];
        if (!isDirectory) {
            if ([source.pathExtension.lowercaseString isEqualToString:@"md"]) {
                [tasks addObjectsFromArray:[self cachedDatedTasksFromFile:source watchPaths:watchPaths error:error]];
            }
            continue;
        }

        NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:[NSURL fileURLWithPath:source]
                                                       includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                                          options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                     errorHandler:nil];
        for (NSURL *url in enumerator) {
            NSNumber *isDir = nil;
            [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
            if (isDir.boolValue) {
                [watchPaths addObject:url.path];
                NSString *name = url.lastPathComponent;
                if ([name isEqualToString:@".obsidian"] || [name isEqualToString:@".trash"] || [name isEqualToString:@"附件"] || [name.lowercaseString isEqualToString:@"attachments"]) {
                    [enumerator skipDescendants];
                }
                continue;
            }

            if (![url.pathExtension.lowercaseString isEqualToString:@"md"]) {
                continue;
            }

            scannedFileCount += 1;
            if (scannedFileCount > 2000) {
                if (error) {
                    *error = [NSError errorWithDomain:@"ObsidianMenuCalendar" code:6 userInfo:@{NSLocalizedDescriptionKey: @"额外任务来源超过 2000 个 Markdown 文件，已停止继续扫描。"}];
                }
                break;
            }

            [tasks addObjectsFromArray:[self cachedDatedTasksFromFile:url.path watchPaths:watchPaths error:error]];
            if (tasks.count > 10000) {
                if (error) {
                    *error = [NSError errorWithDomain:@"ObsidianMenuCalendar" code:7 userInfo:@{NSLocalizedDescriptionKey: @"额外任务来源超过 10000 条带日期任务，已停止继续加载。"}];
                }
                break;
            }
        }
    }
    return tasks;
}

- (void)reloadDataAndRender {
    self.config = self.config ?: OMCLoadConfig();
    [self.tasksByDate removeAllObjects];
    NSMutableSet<NSString *> *watchPaths = [NSMutableSet set];

    if (!self.config.hasVault) {
        self.showingSettings = YES;
        [self stopWatching];
        [self updateStatusItemTitle];
        [self renderPopoverContent];
        self.dataLoaded = YES;
        self.dataDirty = NO;
        self.loadedDayKey = OMCCanonicalDateKey([NSDate date]);
        return;
    }

    NSString *dailyPath = self.config.dailyNotesPath;
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:dailyPath isDirectory:&isDirectory] || !isDirectory) {
        self.errorMessage = [NSString stringWithFormat:@"每日笔记文件夹不存在：%@", dailyPath];
        [self stopWatching];
        [self updateStatusItemTitle];
        [self renderPopoverContent];
        self.dataLoaded = YES;
        self.dataDirty = NO;
        self.loadedDayKey = OMCCanonicalDateKey([NSDate date]);
        return;
    }
    [watchPaths addObject:dailyPath];

    NSMutableArray<NSDate *> *dates = [NSMutableArray array];
    NSMutableSet<NSString *> *dateKeys = [NSMutableSet set];
    void (^addDate)(NSDate *) = ^(NSDate *date) {
        NSString *key = OMCCanonicalDateKey(date);
        if (![dateKeys containsObject:key]) {
            [dateKeys addObject:key];
            [dates addObject:OMCStartOfDay(date)];
        }
    };
    for (NSDate *date in OMCDatesForVisibleMonth(self.visibleMonth)) {
        addDate(date);
    }
    NSDate *today = OMCStartOfDay([NSDate date]);
    for (NSInteger offset = 0; offset <= self.config.lookAheadDays; offset++) {
        addDate([OMCCalendar() dateByAddingUnit:NSCalendarUnitDay value:offset toDate:today options:0]);
    }
    addDate(self.selectedDate);

    NSError *loadError = nil;
    for (NSDate *date in dates) {
        NSArray<OMCTask *> *tasks = [self cachedTasksForDate:date watchPaths:watchPaths error:&loadError];
        self.tasksByDate[OMCCanonicalDateKey(date)] = tasks ?: @[];
    }

    NSArray<OMCTask *> *overdueDailyTasks = [self cachedOverdueDailyTasksWithWatchPaths:watchPaths error:&loadError];
    for (OMCTask *task in overdueDailyTasks) {
        NSString *key = OMCCanonicalDateKey(task.date);
        if ([dateKeys containsObject:key]) {
            continue;
        }
        NSMutableArray<OMCTask *> *merged = [self.tasksByDate[key] mutableCopy] ?: [NSMutableArray array];
        [merged addObject:task];
        self.tasksByDate[key] = merged;
    }

    NSArray<OMCTask *> *extraTasks = [self cachedExtraTasksWithWatchPaths:watchPaths error:&loadError];
    for (OMCTask *task in extraTasks) {
        NSString *key = OMCCanonicalDateKey(task.date);
        NSMutableArray<OMCTask *> *merged = [self.tasksByDate[key] mutableCopy] ?: [NSMutableArray array];
        [merged addObject:task];
        self.tasksByDate[key] = merged;
    }
    for (NSString *key in self.tasksByDate.allKeys) {
        self.tasksByDate[key] = OMCSortedTasks(self.tasksByDate[key] ?: @[]);
    }

    self.errorMessage = loadError.localizedDescription;
    [self startWatchingPaths:watchPaths.allObjects];
    [self updateStatusItemTitle];
    [self renderPopoverContent];
    self.dataLoaded = YES;
    self.dataDirty = NO;
    self.loadedDayKey = OMCCanonicalDateKey([NSDate date]);
}

- (void)renderPopoverContent {
    OMCFlippedView *root = [[OMCFlippedView alloc] initWithFrame:NSMakeRect(0, 0, OMCWidth, OMCHeight)];
    root.wantsLayer = YES;
    root.layer.backgroundColor = OMCPanelFillColor().CGColor;
    root.layer.cornerRadius = 16;
    root.layer.masksToBounds = YES;

    NSVisualEffectView *effect = [[NSVisualEffectView alloc] initWithFrame:root.bounds];
    effect.material = NSVisualEffectMaterialFullScreenUI;
    effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effect.state = NSVisualEffectStateActive;
    effect.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    effect.wantsLayer = YES;
    effect.layer.cornerRadius = 16;
    effect.layer.masksToBounds = YES;
    [root addSubview:effect];

    OMCGlassOverlayView *glass = [[OMCGlassOverlayView alloc] initWithFrame:root.bounds];
    glass.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [root addSubview:glass];

    [self addHeaderToView:root];
    [self addDividerToView:root y:52];

    if (self.showingSettings || !self.config.hasVault) {
        [self addSettingsToView:root y:66];
    } else {
        [self addCalendarToView:root y:60];
        [self addDividerToView:root y:312];
        [self addTaskListToView:root y:313 height:OMCHeight - 313];
    }

    self.viewController.view = root;
    self.calendarPanel.contentView = root;
}

- (NSTextField *)labelWithText:(NSString *)text frame:(NSRect)frame font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = text ?: @"";
    label.font = font;
    label.textColor = color;
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

- (NSButton *)plainButtonWithTitle:(NSString *)title imageName:(NSString *)imageName frame:(NSRect)frame action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.title = title ?: @"";
    if (imageName) {
        button.image = [NSImage imageWithSystemSymbolName:imageName accessibilityDescription:title];
    }
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    button.target = self;
    button.action = action;
    return button;
}

- (OMCChromeButton *)chromeButtonWithTitle:(NSString *)title frame:(NSRect)frame pill:(BOOL)pill action:(SEL)action {
    OMCChromeButton *button = [[OMCChromeButton alloc] initWithFrame:frame];
    button.title = title ?: @"";
    button.pillStyle = pill;
    button.labelSize = pill ? 13 : 19;
    button.target = self;
    button.action = action;
    return button;
}

- (void)addHeaderToView:(NSView *)root {
    NSString *monthTitle = OMCMonthTitle(self.visibleMonth);
    NSTextField *title = [self labelWithText:monthTitle
                                       frame:NSMakeRect(16, 13, 92, 23)
                                        font:[NSFont systemFontOfSize:15 weight:NSFontWeightSemibold]
                                       color:OMCTextColor()];
    [root addSubview:title];

    CGFloat right = OMCWidth - 14;
    OMCChromeButton *settings = [self chromeButtonWithTitle:@"⚙︎" frame:NSMakeRect(right - 24, 13, 24, 24) pill:NO action:@selector(showSettings:)];
    settings.labelSize = 17;
    [root addSubview:settings];

    OMCChromeButton *next = [self chromeButtonWithTitle:@"›" frame:NSMakeRect(right - 51, 13, 24, 24) pill:NO action:@selector(nextMonth:)];
    next.labelSize = 22;
    [root addSubview:next];

    OMCChromeButton *today = [self chromeButtonWithTitle:@"今天" frame:NSMakeRect(right - 96, 13, 42, 24) pill:NO action:@selector(goToToday:)];
    today.labelSize = 14;
    today.labelColor = OMCAccentColor();
    today.fontName = @"HiraginoSansGB-W6";
    today.fontWeight = NSFontWeightSemibold;
    [root addSubview:today];

    OMCChromeButton *prev = [self chromeButtonWithTitle:@"‹" frame:NSMakeRect(right - 120, 13, 24, 24) pill:NO action:@selector(previousMonth:)];
    prev.labelSize = 22;
    [root addSubview:prev];
}

- (void)addDividerToView:(NSView *)root y:(CGFloat)y {
    NSView *divider = [[NSView alloc] initWithFrame:NSMakeRect(14, y, OMCWidth - 28, 1)];
    divider.wantsLayer = YES;
    divider.layer.backgroundColor = OMCDividerColor().CGColor;
    [root addSubview:divider];
}

- (void)addCalendarToView:(NSView *)root y:(CGFloat)y {
    NSArray<NSString *> *weekdays = @[@"周日", @"周一", @"周二", @"周三", @"周四", @"周五", @"周六"];
    CGFloat left = 14;
    CGFloat cellW = (OMCWidth - 28) / 7.0;
    for (NSUInteger i = 0; i < weekdays.count; i++) {
        NSTextField *label = [self labelWithText:weekdays[i]
                                           frame:NSMakeRect(left + i * cellW, y, cellW, 18)
                                            font:[NSFont systemFontOfSize:11 weight:NSFontWeightMedium]
                                           color:OMCSecondaryTextColor()];
        label.alignment = NSTextAlignmentCenter;
        [root addSubview:label];
    }

    NSArray<NSDate *> *dates = OMCDatesForVisibleMonth(self.visibleMonth);
    CGFloat gridTop = y + 22;
    CGFloat cellH = 45;
    NSUInteger visibleDayCount = MIN(dates.count, OMCVisibleCalendarRows * 7);
    for (NSUInteger i = 0; i < visibleDayCount; i++) {
        NSDate *date = dates[i];
        NSUInteger row = i / 7;
        NSUInteger col = i % 7;
        OMCDayCell *cell = [[OMCDayCell alloc] initWithFrame:NSMakeRect(left + col * cellW, gridTop + row * cellH, cellW, cellH)];
        cell.date = date;
        cell.visibleMonth = self.visibleMonth;
        cell.selectedDate = self.selectedDate;
        cell.tasks = [self tasksForDate:date];
        cell.dotThresholdOne = self.config.dotThresholdOne;
        cell.dotThresholdTwo = self.config.dotThresholdTwo;
        cell.dotThresholdThree = self.config.dotThresholdThree;
        cell.target = self;
        cell.action = @selector(selectDay:);
        cell.dropDelegate = self;
        [root addSubview:cell];
    }
}

- (void)addTaskListToView:(NSView *)root y:(CGFloat)y height:(CGFloat)height {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, y, OMCWidth, height)];
    scroll.hasVerticalScroller = YES;
    scroll.scrollerStyle = NSScrollerStyleOverlay;
    scroll.autohidesScrollers = YES;
    scroll.verticalScrollElasticity = NSScrollElasticityAllowed;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;

    OMCFlippedView *document = [[OMCFlippedView alloc] initWithFrame:NSMakeRect(0, 0, OMCWidth, 800)];
    CGFloat cursor = 0;
    NSArray<OMCTask *> *selectedOpenTasks = [self tasksForDate:self.selectedDate done:NO];
    NSArray<OMCTask *> *selectedDoneTasks = [self tasksForDate:self.selectedDate done:YES];
    NSString *selectedTitle = [OMCCalendar() isDateInToday:self.selectedDate] ? @"今天" : OMCShortDate(self.selectedDate);
    NSTextField *titleLabel = [self labelWithText:selectedTitle
                                            frame:NSMakeRect(14, cursor + 10, OMCWidth - 28, 16)
                                             font:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]
                                            color:[OMCSecondaryTextColor() colorWithAlphaComponent:0.95]];
    [document addSubview:titleLabel];

    OMCChromeButton *copy = [self chromeButtonWithTitle:@"⧉" frame:NSMakeRect(OMCWidth - 32, cursor + 7, 20, 20) pill:NO action:@selector(copySelectedDateTasks:)];
    copy.labelSize = 14;
    copy.labelColor = [OMCSecondaryTextColor() colorWithAlphaComponent:0.62];
    [document addSubview:copy];

    cursor += 34;
    [self addInlineTaskInputToView:document y:cursor];
    cursor += 40;

    NSArray<OMCTask *> *overdueTasks = [self overdueTasks];
    if (overdueTasks.count > 0) {
        cursor = [self addTaskSectionToView:document title:@"已过期" empty:@"" tasks:overdueTasks y:cursor showsDate:YES allowsAdd:NO highlightsOverdue:YES];
        [self addDividerToView:document y:cursor + 4];
        cursor += 12;
    }
    for (OMCTask *task in selectedOpenTasks) {
        [self addTaskRowToView:document task:task y:cursor showsDate:NO highlightsOverdue:NO];
        cursor += 58;
    }
    if (selectedDoneTasks.count > 0) {
        cursor = [self addTaskSectionToView:document title:@"已完成" empty:@"" tasks:selectedDoneTasks y:cursor showsDate:NO allowsAdd:NO highlightsOverdue:NO];
    }
    [self addDividerToView:document y:cursor + 4];
    cursor += 12;
    cursor = [self addTaskSectionToView:document title:@"即将到来" empty:@"未来几天没有待办" tasks:[self upcomingTasks] y:cursor showsDate:YES allowsAdd:NO highlightsOverdue:NO];

    CGFloat footerY = cursor + 8;
    OMCChromeButton *open = [self chromeButtonWithTitle:@"打开当天笔记" frame:NSMakeRect(12, footerY, 96, 22) pill:NO action:@selector(openDailyNote:)];
    open.labelSize = 12;
    open.labelColor = [OMCSecondaryTextColor() colorWithAlphaComponent:0.82];
    [document addSubview:open];
    OMCChromeButton *refresh = [self chromeButtonWithTitle:@"刷新" frame:NSMakeRect(OMCWidth - 58, footerY, 42, 22) pill:NO action:@selector(refresh:)];
    refresh.labelSize = 12;
    refresh.labelColor = [OMCSecondaryTextColor() colorWithAlphaComponent:0.82];
    [document addSubview:refresh];
    cursor = footerY + 36;

    if (self.errorMessage.length > 0) {
        NSTextField *error = [self labelWithText:self.errorMessage
                                           frame:NSMakeRect(12, cursor, OMCWidth - 24, 34)
                                            font:[NSFont systemFontOfSize:11 weight:NSFontWeightMedium]
                                           color:OMCAccentColor()];
        error.lineBreakMode = NSLineBreakByWordWrapping;
        [document addSubview:error];
        cursor += 42;
    }

    document.frame = NSMakeRect(0, 0, OMCWidth, MAX(height + 1, cursor));
    scroll.documentView = document;
    [root addSubview:scroll];
}

- (CGFloat)addTaskSectionToView:(NSView *)view title:(NSString *)title empty:(NSString *)empty tasks:(NSArray<OMCTask *> *)tasks y:(CGFloat)y showsDate:(BOOL)showsDate allowsAdd:(BOOL)allowsAdd highlightsOverdue:(BOOL)highlightsOverdue {
    NSTextField *titleLabel = [self labelWithText:title
                                            frame:NSMakeRect(14, y + 10, OMCWidth - 28, 16)
                                             font:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]
                                            color:[OMCSecondaryTextColor() colorWithAlphaComponent:0.95]];
    [view addSubview:titleLabel];

    if (allowsAdd) {
        OMCChromeButton *copy = [self chromeButtonWithTitle:@"⧉" frame:NSMakeRect(OMCWidth - 32, y + 7, 20, 20) pill:NO action:@selector(copySelectedDateTasks:)];
        copy.labelSize = 14;
        copy.labelColor = [OMCSecondaryTextColor() colorWithAlphaComponent:0.62];
        [view addSubview:copy];
    }

    CGFloat cursor = y + 34;
    if (allowsAdd) {
        [self addInlineTaskInputToView:view y:cursor];
        cursor += 40;
    }

    if (tasks.count == 0) {
        if (allowsAdd) {
            return cursor + 2;
        }
        OMCEmptyStateView *emptyView = [[OMCEmptyStateView alloc] initWithFrame:NSMakeRect(14, cursor, OMCWidth - 28, 30)];
        emptyView.text = empty;
        [view addSubview:emptyView];
        return cursor + 34;
    }

    for (OMCTask *task in tasks) {
        [self addTaskRowToView:view task:task y:cursor showsDate:showsDate highlightsOverdue:highlightsOverdue];
        cursor += 58;
    }
    return cursor;
}

- (void)addInlineTaskInputToView:(NSView *)view y:(CGFloat)y {
    CGFloat inputX = 42;
    CGFloat inputRight = OMCWidth - 14;
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(inputX, y, inputRight - inputX, 28)];
    input.placeholderString = @"新建任务";
    input.stringValue = self.inlineDraftText ?: @"";
    input.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular];
    input.textColor = OMCTextColor();
    input.delegate = self;
    input.target = self;
    input.action = @selector(confirmInlineTaskInput:);
    input.bezelStyle = NSTextFieldRoundedBezel;
    input.focusRingType = NSFocusRingTypeExterior;
    input.editable = YES;
    input.selectable = YES;
    [view addSubview:input];
    self.inlineTaskInput = input;

    OMCChromeButton *add = [self chromeButtonWithTitle:@"＋" frame:NSMakeRect(14, y + 3, 22, 22) pill:NO action:@selector(addTask:)];
    add.labelSize = 16;
    add.labelColor = [OMCAccentColor() colorWithAlphaComponent:0.62];
    [view addSubview:add];
}

- (void)addTaskRowToView:(NSView *)view task:(OMCTask *)task y:(CGFloat)y showsDate:(BOOL)showsDate highlightsOverdue:(BOOL)highlightsOverdue {
    NSMenu *taskMenu = [self taskContextMenuForTask:task];

    OMCRowBackgroundView *background = [[OMCRowBackgroundView alloc] initWithFrame:NSMakeRect(8, y, OMCWidth - 16, 54)];
    background.menu = taskMenu;
    [view addSubview:background];

    OMCTaskButton *check = [[OMCTaskButton alloc] initWithFrame:NSMakeRect(14, y + 16, 20, 20)];
    check.task = task;
    check.overrideColor = highlightsOverdue ? OMCOverdueColor() : nil;
    check.bordered = NO;
    check.title = @"";
    check.image = nil;
    check.target = self;
    check.action = @selector(toggleTask:);
    check.menu = taskMenu;
    [view addSubview:check];

    OMCColorBarView *bar = [[OMCColorBarView alloc] initWithFrame:NSMakeRect(42, y + 9, 3, 38)];
    NSColor *rowColor = highlightsOverdue ? OMCOverdueColor() : OMCColorForTask(task);
    bar.fillColor = [rowColor colorWithAlphaComponent:task.done ? 0.35 : 0.9];
    bar.menu = taskMenu;
    [view addSubview:bar];

    CGFloat textX = 54;
    CGFloat timeWidth = 56;
    CGFloat timeX = OMCWidth - 14 - timeWidth;
    CGFloat textWidth = timeX - textX - 10;
    NSTextField *title = [self labelWithText:task.title.length > 0 ? task.title : @"未命名任务"
                                       frame:NSMakeRect(textX, y + 8, textWidth, 19)
                                        font:[NSFont systemFontOfSize:13.5 weight:NSFontWeightSemibold]
                                       color:task.done ? OMCSecondaryTextColor() : (highlightsOverdue ? OMCOverdueColor() : OMCTextColor())];
    if (task.done) {
        NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:title.stringValue attributes:@{
            NSFontAttributeName: title.font,
            NSForegroundColorAttributeName: title.textColor,
            NSStrikethroughStyleAttributeName: @(NSUnderlineStyleSingle)
        }];
        title.attributedStringValue = attr;
    }
    title.menu = taskMenu;
    [view addSubview:title];

    NSMutableArray<NSString *> *subtitleParts = [NSMutableArray array];
    if (showsDate) {
        [subtitleParts addObject:OMCShortDate(task.date)];
    }
    if (task.tags.count > 0) {
        [subtitleParts addObject:[task.tags componentsJoinedByString:@" "]];
    }
    if (task.recurrenceText.length > 0) {
        [subtitleParts addObject:[NSString stringWithFormat:@"🔁 %@", task.recurrenceText]];
    }
    NSString *subtitleText = subtitleParts.count > 0 ? [subtitleParts componentsJoinedByString:@" · "] : task.filePath.lastPathComponent.stringByDeletingPathExtension;
    NSTextField *subtitle = [self labelWithText:subtitleText
                                          frame:NSMakeRect(textX, y + 31, textWidth, 16)
                                          font:[NSFont systemFontOfSize:11 weight:NSFontWeightMedium]
                                          color:highlightsOverdue ? [OMCOverdueColor() colorWithAlphaComponent:0.62] : [OMCSecondaryTextColor() colorWithAlphaComponent:0.82]];
    subtitle.menu = taskMenu;
    [view addSubview:subtitle];

    NSString *timeDisplay = task.timeText.length > 0 ? task.timeText : @"全天";
    NSColor *timeColor = highlightsOverdue ? [OMCOverdueColor() colorWithAlphaComponent:0.82] : (task.timeText.length > 0 ? (task.done ? [OMCSecondaryTextColor() colorWithAlphaComponent:0.62] : OMCTextColor()) : [OMCSecondaryTextColor() colorWithAlphaComponent:0.78]);
    CGFloat timeFontSize = task.timeText.length > 0 ? 12.5 : 11.5;
    NSTextField *time = [self labelWithText:timeDisplay
                                      frame:NSMakeRect(timeX, y + 10, timeWidth, 18)
                                      font:[NSFont systemFontOfSize:timeFontSize weight:NSFontWeightSemibold]
                                      color:timeColor];
    time.alignment = NSTextAlignmentRight;
    time.menu = taskMenu;
    [view addSubview:time];

    OMCTaskDragView *dragView = [[OMCTaskDragView alloc] initWithFrame:NSMakeRect(textX - 2, y + 3, OMCWidth - textX - 8, 48)];
    dragView.task = task;
    dragView.menu = taskMenu;
    [view addSubview:dragView];
}

- (NSMenu *)taskContextMenuForTask:(OMCTask *)task {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];

    NSMenuItem *edit = [[NSMenuItem alloc] initWithTitle:@"编辑任务" action:@selector(editTaskFromMenu:) keyEquivalent:@""];
    edit.target = self;
    edit.representedObject = task;
    [menu addItem:edit];

    NSMenuItem *delete = [[NSMenuItem alloc] initWithTitle:@"删除任务" action:@selector(deleteTaskFromMenu:) keyEquivalent:@""];
    delete.target = self;
    delete.representedObject = task;
    [menu addItem:delete];

    return menu;
}

- (void)addSettingsToView:(NSView *)root y:(CGFloat)y {
    NSTextField *title = [self labelWithText:@"Obsidian 每日任务"
                                       frame:NSMakeRect(18, y, OMCWidth - 36, 26)
                                        font:[NSFont systemFontOfSize:20 weight:NSFontWeightBold]
                                       color:OMCTextColor()];
    [root addSubview:title];

    CGFloat cursor = y + 46;
    [self addFieldLabel:@"主文件夹（每日记录）" root:root y:cursor];
    self.vaultField = [[NSTextField alloc] initWithFrame:NSMakeRect(18, cursor + 19, OMCWidth - 112, 25)];
    self.vaultField.stringValue = self.config.vaultPath ?: @"";
    [root addSubview:self.vaultField];
    NSButton *choose = [self plainButtonWithTitle:@"选择" imageName:nil frame:NSMakeRect(OMCWidth - 84, cursor + 18, 66, 27) action:@selector(chooseVault:)];
    [root addSubview:choose];

    cursor += 58;
    [self addFieldLabel:@"额外任务来源（文件/文件夹，可留空）" root:root y:cursor];
    self.folderField = [[NSTextField alloc] initWithFrame:NSMakeRect(18, cursor + 19, OMCWidth - 36, 25)];
    self.folderField.stringValue = self.config.dailyFolder ?: @"";
    self.folderField.placeholderString = @"日程 或 【日程】定时任务.md";
    [root addSubview:self.folderField];

    cursor += 58;
    [self addFieldLabel:@"日期文件名格式" root:root y:cursor];
    self.formatField = [[NSTextField alloc] initWithFrame:NSMakeRect(18, cursor + 19, 166, 25)];
    self.formatField.stringValue = self.config.dateFormat ?: @"yyyy-MM-dd";
    [root addSubview:self.formatField];

    [self addFieldLabel:@"即将到来天数" root:root y:cursor x:214];
    self.lookAheadField = [[NSTextField alloc] initWithFrame:NSMakeRect(214, cursor + 19, 64, 25)];
    self.lookAheadField.stringValue = [NSString stringWithFormat:@"%ld", (long)self.config.lookAheadDays];
    [root addSubview:self.lookAheadField];

    cursor += 56;
    [self addFieldLabel:@"任务强调色" root:root y:cursor];
    self.accentColorWell = [[OMCRoundColorWell alloc] initWithFrame:NSMakeRect(18, cursor + 17, 34, 34)];
    self.accentColorWell.color = OMCColorFromHex(self.config.accentHexColor, OMCTaskTintColor());
    [root addSubview:self.accentColorWell];

    cursor += 56;
    [self addFieldLabel:@"任务圆点阈值" root:root y:cursor];
    NSArray<NSTextField *> *dotFields = @[
        [[NSTextField alloc] initWithFrame:NSMakeRect(18, cursor + 20, 42, 25)],
        [[NSTextField alloc] initWithFrame:NSMakeRect(104, cursor + 20, 42, 25)],
        [[NSTextField alloc] initWithFrame:NSMakeRect(190, cursor + 20, 42, 25)]
    ];
    NSArray<NSString *> *dotLabels = @[@"1点", @"2点", @"3点"];
    NSArray<NSNumber *> *dotValues = @[@(self.config.dotThresholdOne), @(self.config.dotThresholdTwo), @(self.config.dotThresholdThree)];
    for (NSUInteger index = 0; index < dotFields.count; index++) {
        NSTextField *field = dotFields[index];
        field.stringValue = [NSString stringWithFormat:@"%ld", (long)dotValues[index].integerValue];
        field.alignment = NSTextAlignmentCenter;
        [root addSubview:field];

        NSTextField *label = [self labelWithText:dotLabels[index]
                                           frame:NSMakeRect(NSMaxX(field.frame) + 6, cursor + 25, 34, 15)
                                            font:[NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold]
                                           color:OMCSecondaryTextColor()];
        [root addSubview:label];
    }
    self.dotOneField = dotFields[0];
    self.dotTwoField = dotFields[1];
    self.dotThreeField = dotFields[2];

    cursor += 58;
    self.launchAtLoginButton = [[NSButton alloc] initWithFrame:NSMakeRect(18, cursor + 4, OMCWidth - 36, 22)];
    self.launchAtLoginButton.buttonType = NSButtonTypeSwitch;
    self.launchAtLoginButton.title = @"开机自动启动";
    self.launchAtLoginButton.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    self.launchAtLoginButton.state = OMCLoginItemEnabled() ? NSControlStateValueOn : NSControlStateValueOff;
    [root addSubview:self.launchAtLoginButton];

    if (self.errorMessage.length > 0) {
        NSTextField *error = [self labelWithText:self.errorMessage
                                           frame:NSMakeRect(18, cursor + 36, OMCWidth - 36, 52)
                                            font:[NSFont systemFontOfSize:11 weight:NSFontWeightMedium]
                                           color:OMCAccentColor()];
        error.lineBreakMode = NSLineBreakByWordWrapping;
        [root addSubview:error];
    }

    NSButton *quit = [self plainButtonWithTitle:@"退出应用" imageName:nil frame:NSMakeRect(18, OMCHeight - 44, 78, 28) action:@selector(quit:)];
    [root addSubview:quit];

    NSButton *cancel = [self plainButtonWithTitle:@"取消" imageName:nil frame:NSMakeRect(OMCWidth - 172, OMCHeight - 44, 64, 28) action:@selector(cancelSettings:)];
    cancel.enabled = self.config.hasVault;
    [root addSubview:cancel];

    NSButton *save = [self plainButtonWithTitle:@"保存并读取" imageName:nil frame:NSMakeRect(OMCWidth - 100, OMCHeight - 44, 82, 28) action:@selector(saveSettings:)];
    save.keyEquivalent = @"\r";
    [root addSubview:save];
}

- (void)addFieldLabel:(NSString *)text root:(NSView *)root y:(CGFloat)y {
    [self addFieldLabel:text root:root y:y x:18];
}

- (void)addFieldLabel:(NSString *)text root:(NSView *)root y:(CGFloat)y x:(CGFloat)x {
    NSTextField *label = [self labelWithText:text
                                       frame:NSMakeRect(x, y, 220, 15)
                                        font:[NSFont systemFontOfSize:11 weight:NSFontWeightSemibold]
                                       color:OMCSecondaryTextColor()];
    [root addSubview:label];
}

- (void)previousMonth:(id)sender {
    self.visibleMonth = [OMCCalendar() dateByAddingUnit:NSCalendarUnitMonth value:-1 toDate:self.visibleMonth options:0];
    self.inlineDraftText = @"";
    self.inlineInputActive = NO;
    [self reloadDataAndRender];
}

- (void)nextMonth:(id)sender {
    self.visibleMonth = [OMCCalendar() dateByAddingUnit:NSCalendarUnitMonth value:1 toDate:self.visibleMonth options:0];
    self.inlineDraftText = @"";
    self.inlineInputActive = NO;
    [self reloadDataAndRender];
}

- (void)goToToday:(id)sender {
    self.selectedDate = OMCStartOfDay([NSDate date]);
    NSDate *targetMonth = [self monthStartForDate:self.selectedDate];
    BOOL monthChanged = ![OMCCalendar() isDate:targetMonth equalToDate:self.visibleMonth toUnitGranularity:NSCalendarUnitMonth];
    self.visibleMonth = targetMonth;
    self.inlineDraftText = @"";
    self.inlineInputActive = NO;
    if (monthChanged || self.dataDirty || !self.dataLoaded) {
        [self reloadDataAndRender];
    } else {
        [self renderPopoverContent];
    }
}

- (void)selectDay:(OMCDayCell *)sender {
    self.selectedDate = OMCStartOfDay(sender.date);
    BOOL monthChanged = NO;
    if (![OMCCalendar() isDate:self.selectedDate equalToDate:self.visibleMonth toUnitGranularity:NSCalendarUnitMonth]) {
        self.visibleMonth = [self monthStartForDate:self.selectedDate];
        monthChanged = YES;
    }
    self.inlineDraftText = @"";
    self.inlineInputActive = NO;
    if (monthChanged || self.dataDirty || !self.dataLoaded) {
        [self reloadDataAndRender];
    } else {
        [self renderPopoverContent];
    }
}

- (OMCTask *)taskForIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return nil;
    }
    for (NSArray<OMCTask *> *tasks in self.tasksByDate.allValues) {
        for (OMCTask *task in tasks) {
            if ([task.identifier isEqualToString:identifier]) {
                return task;
            }
        }
    }
    return nil;
}

- (BOOL)dayCell:(OMCDayCell *)cell acceptDraggedTaskIdentifier:(NSString *)identifier {
    OMCTask *task = [self taskForIdentifier:identifier];
    if (!task) {
        self.errorMessage = @"没有找到要移动的任务，请刷新后再试。";
        [self reloadDataAndRender];
        return NO;
    }

    NSDate *targetDate = OMCStartOfDay(cell.date);
    NSError *error = nil;
    if (!OMCMoveTaskToDate(self.config, task, targetDate, &error)) {
        self.errorMessage = error.localizedDescription ?: @"移动任务失败。";
        [self.taskCache removeAllObjects];
        [self reloadDataAndRender];
        return NO;
    }

    self.selectedDate = targetDate;
    if (![OMCCalendar() isDate:self.selectedDate equalToDate:self.visibleMonth toUnitGranularity:NSCalendarUnitMonth]) {
        self.visibleMonth = [self monthStartForDate:self.selectedDate];
    }
    self.inlineDraftText = @"";
    self.inlineInputActive = NO;
    self.errorMessage = nil;
    [self.taskCache removeAllObjects];
    [self reloadDataAndRender];
    return YES;
}

- (void)toggleTask:(OMCTaskButton *)sender {
    NSError *error = nil;
    BOOL completing = !sender.task.done;
    NSDate *completionDate = [NSDate date];
    if (!OMCSetTaskDone(sender.task, completing, completionDate, &error)) {
        self.errorMessage = error.localizedDescription;
    } else {
        self.errorMessage = nil;
        if (completing) {
            NSDate *nextDate = OMCNextRecurrenceDate(sender.task, completionDate);
            NSString *nextBody = OMCRecurringTaskBodyForNextDate(sender.task, nextDate);
            if (nextBody.length > 0) {
                NSError *recurrenceError = nil;
                BOOL appended = OMCPathIsDailyNoteForTask(self.config, sender.task)
                    ? OMCAppendTaskToDailyNote(self.config, nextDate, nextBody, &recurrenceError)
                    : OMCAppendTaskToMarkdownFile(sender.task.filePath, nextBody, &recurrenceError);
                if (!appended) {
                    self.errorMessage = [NSString stringWithFormat:@"已完成当前任务，但生成下一次循环任务失败：%@", recurrenceError.localizedDescription ?: @"未知错误"];
                }
            }
        }
    }
    [self.taskCache removeAllObjects];
    [self reloadDataAndRender];
}

- (void)editTaskFromMenu:(NSMenuItem *)sender {
    OMCTask *task = sender.representedObject;
    if (!task) {
        return;
    }

    [self removeOutsideClickMonitor];
    [self removeKeyboardMonitor];
    self.inlineInputActive = NO;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"编辑任务";
    alert.informativeText = @"会保留原来的日期、标签、循环规则和完成状态。";
    [alert addButtonWithTitle:@"保存"];
    [alert addButtonWithTitle:@"取消"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 320, 28)];
    input.stringValue = OMCEditableTextForTask(task);
    input.placeholderString = @"任务内容 08:30";
    alert.accessoryView = input;
    [alert.window setInitialFirstResponder:input];

    [NSApp activateIgnoringOtherApps:YES];
    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        NSError *error = nil;
        if (!OMCUpdateTaskText(task, input.stringValue, &error)) {
            self.errorMessage = error.localizedDescription;
        } else {
            self.errorMessage = nil;
        }
        [self.taskCache removeAllObjects];
        [self reloadDataAndRender];
    }

    if (self.calendarPanel.isVisible) {
        [self installOutsideClickMonitor];
        [self installKeyboardMonitor];
    }
}

- (void)deleteTaskFromMenu:(NSMenuItem *)sender {
    OMCTask *task = sender.representedObject;
    if (!task) {
        return;
    }

    [self removeOutsideClickMonitor];
    [self removeKeyboardMonitor];
    self.inlineInputActive = NO;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"删除任务？";
    alert.informativeText = task.title.length > 0 ? task.title : @"这条任务会从原 Markdown 文件中删除。";
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"删除"];
    [alert addButtonWithTitle:@"取消"];

    [NSApp activateIgnoringOtherApps:YES];
    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        NSError *error = nil;
        if (!OMCDeleteTask(task, &error)) {
            self.errorMessage = error.localizedDescription;
        } else {
            self.errorMessage = nil;
        }
        [self.taskCache removeAllObjects];
        [self reloadDataAndRender];
    }

    if (self.calendarPanel.isVisible) {
        [self installOutsideClickMonitor];
        [self installKeyboardMonitor];
    }
}

- (void)addTask:(id)sender {
    if (!self.config.hasVault) {
        self.errorMessage = @"请先选择 Obsidian Vault。";
        [self renderPopoverContent];
        return;
    }

    if (!self.inlineInputActive) {
        [self focusInlineTaskInput];
        return;
    }

    NSString *taskText = [self.inlineTaskInput.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (taskText.length > 0) {
        [self confirmInlineTaskInput:self.inlineTaskInput];
    } else {
        [self focusInlineTaskInput];
    }
}

- (void)focusInlineTaskInput {
    if (!self.inlineTaskInput || !self.calendarPanel.isVisible) {
        return;
    }

    self.inlineInputActive = YES;
    self.inlineTaskInput.editable = YES;
    self.inlineTaskInput.selectable = YES;

    NSWindow *window = self.calendarPanel;
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyWindow];
    [window makeFirstResponder:self.inlineTaskInput];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        OMCAppDelegate *strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.inlineInputActive || !strongSelf.calendarPanel.isVisible) {
            return;
        }
        NSWindow *currentWindow = strongSelf.calendarPanel;
        [currentWindow makeKeyWindow];
        [currentWindow makeFirstResponder:strongSelf.inlineTaskInput];
    });
}

- (void)confirmInlineTaskInput:(id)sender {
    NSString *taskText = [self.inlineTaskInput.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (taskText.length == 0) {
        [self focusInlineTaskInput];
        return;
    }

    NSError *error = nil;
    if (!OMCAppendTaskToDailyNote(self.config, self.selectedDate, taskText, &error)) {
        self.errorMessage = error.localizedDescription;
        self.inlineDraftText = taskText;
        self.inlineInputActive = YES;
    } else {
        self.errorMessage = nil;
        self.inlineDraftText = @"";
        self.inlineInputActive = NO;
        self.inlineTaskInput.stringValue = @"";
    }

    [self.taskCache removeAllObjects];
    [self reloadDataAndRender];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == self.inlineTaskInput) {
        self.inlineDraftText = self.inlineTaskInput.stringValue ?: @"";
    }
}

- (void)controlTextDidBeginEditing:(NSNotification *)notification {
    if (notification.object == self.inlineTaskInput) {
        self.inlineInputActive = YES;
    }
}

- (void)copySelectedDateTasks:(id)sender {
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObject:OMCClipboardDateTitle(self.selectedDate)];
    for (OMCTask *task in [self tasksForDate:self.selectedDate]) {
        NSString *title = [task.title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (title.length > 0) {
            [lines addObject:title];
        }
    }

    NSString *clipboardText = [lines componentsJoinedByString:@"\n"];
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:clipboardText forType:NSPasteboardTypeString];
}

- (void)positionAddTaskPanel:(NSPanel *)panel {
    NSWindow *popoverWindow = self.calendarPanel;
    NSScreen *screen = popoverWindow.screen ?: NSScreen.mainScreen;
    NSRect visibleFrame = screen.visibleFrame;
    NSRect panelFrame = panel.frame;

    if (!popoverWindow) {
        [panel center];
        return;
    }

    NSRect popoverFrame = popoverWindow.frame;
    CGFloat gap = 10;
    CGFloat x = NSMidX(popoverFrame) - panelFrame.size.width / 2.0;
    CGFloat y = NSMaxY(popoverFrame) + gap;

    if (y + panelFrame.size.height > NSMaxY(visibleFrame)) {
        x = NSMinX(popoverFrame) - panelFrame.size.width - gap;
        y = NSMaxY(popoverFrame) - panelFrame.size.height - 18;
        if (x < NSMinX(visibleFrame) + 8) {
            x = NSMaxX(popoverFrame) + gap;
        }
        if (x + panelFrame.size.width > NSMaxX(visibleFrame) - 8) {
            x = NSMinX(visibleFrame) + 12;
            y = NSMaxY(popoverFrame) - panelFrame.size.height - 18;
        }
    }

    x = MAX(NSMinX(visibleFrame) + 8, MIN(x, NSMaxX(visibleFrame) - panelFrame.size.width - 8));
    y = MAX(NSMinY(visibleFrame) + 8, MIN(y, NSMaxY(visibleFrame) - panelFrame.size.height - 8));
    [panel setFrameOrigin:NSMakePoint(x, y)];
}

- (void)confirmAddTaskDialog:(id)sender {
    NSString *taskText = self.addTaskInput.stringValue ?: @"";
    NSError *error = nil;
    if (!OMCAppendTaskToDailyNote(self.config, self.selectedDate, taskText, &error)) {
        self.errorMessage = error.localizedDescription;
    } else {
        self.errorMessage = nil;
    }

    [self.addTaskPanel close];
    self.addTaskPanel = nil;
    self.addTaskInput = nil;
    [self.taskCache removeAllObjects];
    [self reloadDataAndRender];
}

- (void)cancelAddTaskDialog:(id)sender {
    [self.addTaskPanel close];
    self.addTaskPanel = nil;
    self.addTaskInput = nil;
}

- (void)openDailyNote:(id)sender {
    NSString *path = OMCNotePathForDate(self.config, self.selectedDate);
    [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:path]];
}

- (void)refresh:(id)sender {
    [self reloadDataAndRender];
}

- (void)showSettings:(id)sender {
    self.showingSettings = YES;
    [self renderPopoverContent];
}

- (void)cancelSettings:(id)sender {
    self.showingSettings = NO;
    [self renderPopoverContent];
}

- (void)chooseVault:(id)sender {
    [self removeOutsideClickMonitor];
    [self removeKeyboardMonitor];

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.prompt = @"选择主文件夹";
    panel.directoryURL = self.vaultField.stringValue.length > 0 ? [NSURL fileURLWithPath:self.vaultField.stringValue.stringByExpandingTildeInPath] : nil;
    if ([panel runModal] == NSModalResponseOK) {
        NSString *selectedPath = panel.URL.path.stringByStandardizingPath ?: @"";
        self.vaultField.stringValue = selectedPath;
        [NSApp activateIgnoringOtherApps:YES];
        [self.calendarPanel makeKeyWindow];
        [self.calendarPanel makeFirstResponder:self.vaultField];
    }

    if (self.calendarPanel.isVisible) {
        [self installOutsideClickMonitor];
        [self installKeyboardMonitor];
    }
}

- (void)saveSettings:(id)sender {
    OMCConfig *config = [[OMCConfig alloc] init];
    NSString *vaultPath = [self.vaultField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    config.vaultPath = vaultPath.length > 0 ? vaultPath.stringByExpandingTildeInPath.stringByStandardizingPath : @"";
    config.dailyFolder = self.folderField.stringValue ?: @"";
    config.dateFormat = self.formatField.stringValue.length > 0 ? self.formatField.stringValue : @"yyyy-MM-dd";
    config.accentHexColor = OMCHexFromColor(self.accentColorWell.color);
    NSInteger lookAhead = self.lookAheadField.integerValue;
    config.lookAheadDays = lookAhead > 0 ? lookAhead : 14;
    NSInteger dotOne = self.dotOneField.integerValue;
    NSInteger dotTwo = self.dotTwoField.integerValue;
    NSInteger dotThree = self.dotThreeField.integerValue;
    dotOne = dotOne > 0 ? dotOne : 1;
    dotTwo = dotTwo > dotOne ? dotTwo : dotOne + 1;
    dotThree = dotThree > dotTwo ? dotThree : dotTwo + 1;
    config.dotThresholdOne = dotOne;
    config.dotThresholdTwo = dotTwo;
    config.dotThresholdThree = dotThree;

    NSError *loginError = nil;
    BOOL wantsLaunchAtLogin = self.launchAtLoginButton.state == NSControlStateValueOn;
    BOOL loginSaved = OMCSetLoginItemEnabled(wantsLaunchAtLogin, &loginError);

    self.config = config;
    OMCSaveConfig(config);
    OMCClearResolvedDailyNotesPathCache();
    [self.taskCache removeAllObjects];
    self.showingSettings = NO;
    self.errorMessage = nil;
    [self reloadDataAndRender];
    if (!loginSaved) {
        self.errorMessage = [NSString stringWithFormat:@"开机启动设置失败：%@", loginError.localizedDescription ?: @"未知错误"];
        [self renderPopoverContent];
    }
}

- (void)quit:(id)sender {
    [NSApplication.sharedApplication terminate:nil];
}

- (void)startWatchingPaths:(NSArray<NSString *> *)paths {
    NSMutableSet<NSString *> *requestedPaths = [NSMutableSet set];
    for (NSString *path in paths) {
        NSString *standardized = [path.stringByStandardizingPath copy];
        if (standardized.length > 0) {
            [requestedPaths addObject:standardized];
        }
    }
    if (self.watchedPathSet && [self.watchedPathSet isEqualToSet:requestedPaths]) {
        return;
    }

    [self stopWatching];
    dispatch_queue_t queue = dispatch_queue_create("local.codex.ObsidianMenuCalendar.FileWatcher", DISPATCH_QUEUE_SERIAL);
    NSMutableSet<NSString *> *openedPaths = [NSMutableSet set];
    for (NSString *path in requestedPaths) {
        int fd = open(path.fileSystemRepresentation, O_EVTONLY);
        if (fd < 0) {
            continue;
        }
        dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd, DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_ATTRIB, queue);
        __weak typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(source, ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf scheduleReload];
            });
        });
        dispatch_resume(source);
        [self.watchSources addObject:source];
        [self.watchFDs addObject:@(fd)];
        [openedPaths addObject:path];
    }
    self.watchedPathSet = openedPaths.copy;
}

- (void)stopWatching {
    for (id source in self.watchSources) {
        dispatch_source_cancel((dispatch_source_t)source);
    }
    for (NSNumber *fdNumber in self.watchFDs) {
        close(fdNumber.intValue);
    }
    [self.watchSources removeAllObjects];
    [self.watchFDs removeAllObjects];
    self.watchedPathSet = nil;
}

- (void)scheduleReload {
    self.dataDirty = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadDataAndRender) object:nil];
    [self performSelector:@selector(reloadDataAndRender) withObject:nil afterDelay:0.35];
}

@end

static int OMCRunSelfTest(void) {
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"omc-test-%@", NSUUID.UUID.UUIDString]];
    NSString *daily = [root stringByAppendingPathComponent:@"Daily"];
    [NSFileManager.defaultManager createDirectoryAtPath:daily withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *obsidianConfig = [root stringByAppendingPathComponent:@".obsidian"];
    NSString *assetFolder = [root stringByAppendingPathComponent:@"00-Asset"];
    [NSFileManager.defaultManager createDirectoryAtPath:obsidianConfig withIntermediateDirectories:YES attributes:nil error:nil];
    [NSFileManager.defaultManager createDirectoryAtPath:assetFolder withIntermediateDirectories:YES attributes:nil error:nil];
    [@"{\"folder\":\"00-模板文件\"}" writeToFile:[obsidianConfig stringByAppendingPathComponent:@"templates.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *templateText = @"---\n锻炼:\n英语:\n补剂:\n手机:\n---\n# {{date}}\n### 今日任务\n\n\n### 今日感悟\n";
    [templateText writeToFile:[assetFolder stringByAppendingPathComponent:@"日记模板.md"] atomically:YES encoding:NSUTF8StringEncoding error:nil];

    OMCConfig *config = [[OMCConfig alloc] init];
    config.vaultPath = daily;
    config.dailyFolder = @"";
    config.dateFormat = @"yyyy-MM-dd";
    NSDate *date = OMCStartOfDay([NSDate date]);
    NSString *path = OMCNotePathForDate(config, date);
    NSString *seed = @"# Today\n\n- [ ] 提交季度报告 #Work 16:00\n- [x] 清晨公园慢跑 #Health ✅ 2026-06-11\n";
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [seed writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSMutableSet<NSString *> *watched = [NSMutableSet set];
    NSError *error = nil;
    NSArray<OMCTask *> *tasks = OMCLoadTasksForDate(config, date, watched, &error);
    if (tasks.count != 2) {
        fprintf(stderr, "Expected 2 tasks, got %lu\n", (unsigned long)tasks.count);
        return 1;
    }
    if (![tasks.firstObject.title isEqualToString:@"提交季度报告"] || ![tasks.firstObject.timeText isEqualToString:@"16:00"]) {
        fprintf(stderr, "Time parsing/title cleanup failed: %s / %s\n", (tasks.firstObject.title ?: @"").UTF8String, (tasks.firstObject.timeText ?: @"").UTF8String);
        return 1;
    }
    if (!OMCSetTaskDone(tasks.firstObject, YES, date, &error)) {
        fprintf(stderr, "Toggle failed: %s\n", error.localizedDescription.UTF8String);
        return 1;
    }
    if (!OMCAppendTaskToDailyNote(config, date, @"开会 10:00", &error)) {
        fprintf(stderr, "Append failed: %s\n", error.localizedDescription.UTF8String);
        return 1;
    }
    NSString *updated = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    NSString *expected = [NSString stringWithFormat:@"- [x] 提交季度报告 #Work 16:00 ✅ %@", OMCCompletionDateString(date)];
    if (![updated containsString:expected]) {
        fprintf(stderr, "Writeback did not contain expected line.\n%s\n", updated.UTF8String);
        return 1;
    }
    NSString *expectedAdded = [NSString stringWithFormat:@"- [ ] 开会 10:00 %@", OMCDueDateString(date)];
    if (![updated containsString:@"### 今日任务"] || ![updated containsString:expectedAdded]) {
        fprintf(stderr, "Append did not create expected task section.\n%s\n", updated.UTF8String);
        return 1;
    }
    NSArray<OMCTask *> *updatedTasks = OMCLoadTasksForDate(config, date, watched, &error);
    OMCTask *addedTask = updatedTasks.lastObject;
    if (![addedTask.title isEqualToString:@"开会"] || ![addedTask.timeText isEqualToString:@"10:00"]) {
        fprintf(stderr, "Added task parse failed: %s / %s\n", (addedTask.title ?: @"").UTF8String, (addedTask.timeText ?: @"").UTF8String);
        return 1;
    }
    if (!OMCUpdateTaskText(addedTask, @"改会 11:00", &error)) {
        fprintf(stderr, "Edit task failed: %s\n", error.localizedDescription.UTF8String);
        return 1;
    }
    NSString *editedContent = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    NSString *expectedEdited = [NSString stringWithFormat:@"- [ ] 改会 11:00 %@", OMCDueDateString(date)];
    if (![editedContent containsString:expectedEdited]) {
        fprintf(stderr, "Edit task did not preserve expected metadata.\n%s\n", (editedContent ?: @"").UTF8String);
        return 1;
    }
    NSArray<OMCTask *> *editedTasks = OMCLoadTasksForDate(config, date, watched, &error);
    OMCTask *editedTask = nil;
    for (OMCTask *candidate in editedTasks) {
        if ([candidate.title isEqualToString:@"改会"]) {
            editedTask = candidate;
            break;
        }
    }
    if (!editedTask || !OMCDeleteTask(editedTask, &error)) {
        fprintf(stderr, "Delete task failed: %s\n", error.localizedDescription.UTF8String);
        return 1;
    }
    NSString *deletedContent = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if ([deletedContent containsString:@"改会 11:00"] || [deletedContent containsString:@"开会 10:00"]) {
        fprintf(stderr, "Delete task left edited task behind.\n%s\n", (deletedContent ?: @"").UTF8String);
        return 1;
    }

    NSDate *nestedDate = [OMCDateFormatter(@"yyyy-MM-dd") dateFromString:@"2025-12-19"];
    NSString *nestedFolder = [[daily stringByAppendingPathComponent:@"2025"] stringByAppendingPathComponent:@"2025-12"];
    NSString *nestedPath = [nestedFolder stringByAppendingPathComponent:@"2025-12-19.md"];
    [NSFileManager.defaultManager createDirectoryAtPath:nestedFolder withIntermediateDirectories:YES attributes:nil error:nil];
    [@"# 2025-12-19\n\n- [ ] 子目录历史任务 09:30\n" writeToFile:nestedPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSArray<OMCTask *> *nestedTasks = OMCLoadTasksForDate(config, nestedDate, watched, &error);
    if (nestedTasks.count != 1 || ![nestedTasks.firstObject.title isEqualToString:@"子目录历史任务"]) {
        fprintf(stderr, "Nested daily note loading failed: %lu\n", (unsigned long)nestedTasks.count);
        return 1;
    }

    if (!OMCAppendTaskToDailyNote(config, date, @"拖动测试 12:00", &error)) {
        fprintf(stderr, "Drag seed append failed: %s\n", error.localizedDescription.UTF8String);
        return 1;
    }
    NSArray<OMCTask *> *dragSeedTasks = OMCLoadTasksForDate(config, date, watched, &error);
    OMCTask *dragSeedTask = nil;
    for (OMCTask *candidate in dragSeedTasks) {
        if ([candidate.title isEqualToString:@"拖动测试"]) {
            dragSeedTask = candidate;
            break;
        }
    }
    NSDate *moveDate = [OMCCalendar() dateByAddingUnit:NSCalendarUnitDay value:2 toDate:date options:0];
    if (!dragSeedTask || !OMCMoveTaskToDate(config, dragSeedTask, moveDate, &error)) {
        fprintf(stderr, "Daily task move failed: %s\n", error.localizedDescription.UTF8String);
        return 1;
    }
    NSString *movePath = OMCNotePathForDate(config, moveDate);
    NSString *moveContent = [NSString stringWithContentsOfFile:movePath encoding:NSUTF8StringEncoding error:nil];
    NSString *sourceAfterMove = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    NSString *expectedMovedTask = [NSString stringWithFormat:@"- [ ] 拖动测试 12:00 📅 %@", OMCCanonicalDateKey(moveDate)];
    if ([sourceAfterMove containsString:@"拖动测试 12:00"] || ![moveContent containsString:expectedMovedTask]) {
        fprintf(stderr, "Daily task move did not update files.\nSOURCE:\n%s\nTARGET:\n%s\n", (sourceAfterMove ?: @"").UTF8String, (moveContent ?: @"").UTF8String);
        return 1;
    }

    NSDate *newDate = [OMCCalendar() dateByAddingUnit:NSCalendarUnitDay value:1 toDate:date options:0];
    if (!OMCAppendTaskToDailyNote(config, newDate, @"测试 08:30-09:00", &error)) {
        fprintf(stderr, "Template append failed: %s\n", error.localizedDescription.UTF8String);
        return 1;
    }
    NSString *newPath = OMCNotePathForDate(config, newDate);
    NSString *newContent = [NSString stringWithContentsOfFile:newPath encoding:NSUTF8StringEncoding error:nil];
    NSString *newDateText = OMCCanonicalDateKey(newDate);
    NSString *expectedTemplateTask = [NSString stringWithFormat:@"- [ ] 测试 08:30-09:00 📅 %@", newDateText];
    if (![newContent containsString:[NSString stringWithFormat:@"# %@", newDateText]] ||
        ![newContent containsString:@"锻炼:"] ||
        ![newContent containsString:@"### 今日感悟"] ||
        ![newContent containsString:expectedTemplateTask]) {
        fprintf(stderr, "Template-created daily note is wrong.\n%s\n", (newContent ?: @"").UTF8String);
        return 1;
    }
    NSString *expectedMonthlyFolder = [[daily stringByAppendingPathComponent:[OMCDateFormatter(@"yyyy") stringFromDate:newDate]] stringByAppendingPathComponent:[OMCDateFormatter(@"yyyy-MM") stringFromDate:newDate]];
    if (![newPath.stringByDeletingLastPathComponent isEqualToString:expectedMonthlyFolder]) {
        fprintf(stderr, "New daily note was not created in monthly folder: %s\n", newPath.UTF8String);
        return 1;
    }

    NSDate *chineseYearDate = [OMCDateFormatter(@"yyyy-MM-dd") dateFromString:@"2030-07-05"];
    NSString *chineseYearFolder = [daily stringByAppendingPathComponent:@"2030年"];
    [NSFileManager.defaultManager createDirectoryAtPath:chineseYearFolder withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *chineseYearPath = OMCNotePathForDate(config, chineseYearDate);
    NSString *expectedChineseYearFolder = [chineseYearFolder stringByAppendingPathComponent:@"2030-07"];
    if (![chineseYearPath.stringByDeletingLastPathComponent isEqualToString:expectedChineseYearFolder]) {
        fprintf(stderr, "Chinese year folder was not preferred: %s\n", chineseYearPath.UTF8String);
        return 1;
    }

    NSString *recurringLine = [NSString stringWithFormat:@"- [ ] 跑步 08:00 🔁 every day 📅 %@", OMCCanonicalDateKey(date)];
    OMCTask *recurringTask = OMCParseTaskLine(recurringLine, 0, path, date);
    NSDate *nextRecurringDate = OMCNextRecurrenceDate(recurringTask, date);
    NSString *nextRecurringBody = OMCRecurringTaskBodyForNextDate(recurringTask, nextRecurringDate);
    NSString *nextRecurringDateText = OMCCanonicalDateKey(nextRecurringDate);
    if (![recurringTask.title isEqualToString:@"跑步"] ||
        ![recurringTask.recurrenceText isEqualToString:@"every day"] ||
        ![nextRecurringDateText isEqualToString:newDateText] ||
        ![nextRecurringBody isEqualToString:[NSString stringWithFormat:@"跑步 08:00 🔁 every day 📅 %@", newDateText]]) {
        fprintf(stderr, "Recurring task parsing failed: %s / %s / %s\n", (recurringTask.title ?: @"").UTF8String, (recurringTask.recurrenceText ?: @"").UTF8String, (nextRecurringBody ?: @"").UTF8String);
        return 1;
    }
    if (!OMCAppendTaskToDailyNote(config, nextRecurringDate, nextRecurringBody, &error)) {
        fprintf(stderr, "Recurring append failed: %s\n", error.localizedDescription.UTF8String);
        return 1;
    }
    NSString *recurringContent = [NSString stringWithContentsOfFile:newPath encoding:NSUTF8StringEncoding error:nil];
    NSString *expectedRecurringTask = [NSString stringWithFormat:@"- [ ] 跑步 08:00 🔁 every day 📅 %@", newDateText];
    if (![recurringContent containsString:expectedRecurringTask]) {
        fprintf(stderr, "Recurring-created daily note is wrong.\n%s\n", (recurringContent ?: @"").UTF8String);
        return 1;
    }

    NSString *scheduleFolder = [daily stringByAppendingPathComponent:@"日程"];
    [NSFileManager.defaultManager createDirectoryAtPath:scheduleFolder withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *schedulePath = [scheduleFolder stringByAppendingPathComponent:@"定时任务.md"];
    [@"# 日程\n\n- [ ] giffgaff激活 📅 2026-6-30 🔁 every 170 days\n" writeToFile:schedulePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    config.dailyFolder = @"日程";
    NSArray<NSString *> *extraSources = OMCExtraTaskSourcePaths(config);
    if (extraSources.count != 1 || ![extraSources.firstObject isEqualToString:scheduleFolder.stringByStandardizingPath]) {
        fprintf(stderr, "Extra source path resolution failed: %s\n", (extraSources.firstObject ?: @"").UTF8String);
        return 1;
    }
    NSArray<OMCTask *> *extraTasks = OMCLoadDatedTasksFromFile(schedulePath, watched, &error);
    OMCTask *extraTask = extraTasks.firstObject;
    NSString *extraTaskDate = OMCCanonicalDateKey(extraTask.date);
    NSDate *nextExtraDate = OMCNextRecurrenceDate(extraTask, extraTask.date);
    NSString *nextExtraBody = OMCRecurringTaskBodyForNextDate(extraTask, nextExtraDate);
    if (![extraTask.title isEqualToString:@"giffgaff激活"] ||
        ![extraTaskDate isEqualToString:@"2026-06-30"] ||
        ![OMCCanonicalDateKey(nextExtraDate) isEqualToString:@"2026-12-17"] ||
        ![nextExtraBody isEqualToString:@"giffgaff激活 📅 2026-12-17 🔁 every 170 days"]) {
        fprintf(stderr, "Extra scheduled task parsing failed: %s / %s / %s\n", (extraTask.title ?: @"").UTF8String, (extraTaskDate ?: @"").UTF8String, (nextExtraBody ?: @"").UTF8String);
        return 1;
    }
    if (!OMCAppendTaskToMarkdownFile(schedulePath, nextExtraBody, &error)) {
        fprintf(stderr, "Extra recurring append failed: %s\n", error.localizedDescription.UTF8String);
        return 1;
    }
    NSString *scheduleContent = [NSString stringWithContentsOfFile:schedulePath encoding:NSUTF8StringEncoding error:nil];
    if (![scheduleContent containsString:@"- [ ] giffgaff激活 📅 2026-12-17 🔁 every 170 days"]) {
        fprintf(stderr, "Extra recurring writeback failed.\n%s\n", (scheduleContent ?: @"").UTF8String);
        return 1;
    }
    NSDate *extraMoveDate = [OMCDateFormatter(@"yyyy-MM-dd") dateFromString:@"2026-07-01"];
    if (!OMCMoveTaskToDate(config, extraTask, extraMoveDate, &error)) {
        fprintf(stderr, "Extra task move failed: %s\n", error.localizedDescription.UTF8String);
        return 1;
    }
    NSString *movedScheduleContent = [NSString stringWithContentsOfFile:schedulePath encoding:NSUTF8StringEncoding error:nil];
    if (![movedScheduleContent containsString:@"- [ ] giffgaff激活 📅 2026-07-01 🔁 every 170 days"]) {
        fprintf(stderr, "Extra task move did not replace due date.\n%s\n", (movedScheduleContent ?: @"").UTF8String);
        return 1;
    }

    NSDateFormatter *specialFormatter = OMCDateFormatter(@"yyyy-MM-dd");
    if (![OMCSpecialDayText([specialFormatter dateFromString:@"2026-10-01"]) isEqualToString:@"国庆"] ||
        ![OMCSpecialDayText([specialFormatter dateFromString:@"2026-06-19"]) isEqualToString:@"端午"] ||
        ![OMCSpecialDayText([specialFormatter dateFromString:@"2026-02-04"]) isEqualToString:@"立春"]) {
        fprintf(stderr, "Special calendar subtitle failed.\n");
        return 1;
    }

    printf("Self-test OK\n");
    return 0;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--self-test") == 0) {
            return OMCRunSelfTest();
        }
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        OMCAppDelegate *delegate = [[OMCAppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
