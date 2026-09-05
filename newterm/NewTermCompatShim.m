#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <pthread.h>
#import <stdint.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>
#import <errno.h>
#import <fcntl.h>
#import <sys/file.h>
#import <sys/stat.h>

#import "VT100Types.h"
#import "VT100Terminal.h"

extern void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *result);
extern void MSHookFunction(void *symbol, void *replace, void **result);

typedef struct {
    unsigned short width;
    unsigned short height;
} NTScreenSize;

static void (*originalSetScreenSize)(id, SEL, NTScreenSize);
static void (*originalResize)(id, SEL, int, int);
static void (*originalInitScreen)(id, SEL, int, int);
static void (*originalReadInputStream)(id, SEL, NSData *);
static void (*originalClearScreen)(id, SEL);
static id (*originalAttributedString)(id, SEL);
static void (*originalUpdateTimerFired)(id, SEL);
static int (*originalExecve)(const char *, char *const[], char *const[]);

static void (*originalRootLoadView)(id, SEL);
static void (*originalRootAddTerminal)(id, SEL);
static void (*originalRootRemoveCurrentTerminal)(id, SEL);
static void (*originalRootRemoveAllTerminals)(id, SEL);
static void (*originalRootSelectTerminalAtIndex)(id, SEL, NSInteger);

static BOOL nt_restoringTabs = NO;
static NSInteger nt_launchTabCount = 1;
static const void *nt_restoredRootKey = &nt_restoredRootKey;

static NSString *nt_stateDirectory(void) {
    return @"/var/mobile/.newterm";
}

static void nt_prepareStateDirectory(void) {
    [[NSFileManager defaultManager] createDirectoryAtPath:nt_stateDirectory()
                               withIntermediateDirectories:YES
                                                attributes:@{ NSFilePosixPermissions: @0700 }
                                                     error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/mobile/.newterm/tmp"
                               withIntermediateDirectories:YES
                                                attributes:@{ NSFilePosixPermissions: @0700 }
                                                     error:nil];
}

static NSInteger nt_readIntegerFile(NSString *path, NSInteger fallback) {
    NSString *contents = [NSString stringWithContentsOfFile:path
                                                       encoding:NSUTF8StringEncoding
                                                          error:nil];
    if (!contents.length) {
        return fallback;
    }

    NSInteger value = contents.integerValue;
    return value >= 0 ? value : fallback;
}

static void nt_writeIntegerFile(NSString *path, NSInteger value) {
    [[NSString stringWithFormat:@"%ld\n", (long)value]
        writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static NSInteger nt_clampedTabCount(NSInteger count) {
    return MIN(MAX(count, 1), 32);
}

static NSInteger nt_loadTabCount(void) {
    nt_prepareStateDirectory();
    NSInteger fromFile = nt_readIntegerFile(@"/var/mobile/.newterm/tab-count", 0);
    if (fromFile >= 1) {
        return nt_clampedTabCount(fromFile);
    }

    NSInteger fromDefaults = [[NSUserDefaults standardUserDefaults]
        integerForKey:@"NewTermCompatTabCount"];
    return nt_clampedTabCount(fromDefaults >= 1 ? fromDefaults : 1);
}

static void nt_saveTabCount(NSInteger count) {
    NSInteger clamped = nt_clampedTabCount(count);
    [[NSUserDefaults standardUserDefaults] setInteger:clamped
                                                 forKey:@"NewTermCompatTabCount"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    nt_prepareStateDirectory();
    nt_writeIntegerFile(@"/var/mobile/.newterm/tab-count", clamped);

    NSMutableString *sessions = [NSMutableString string];
    for (NSInteger index = 1; index <= clamped; index++) {
        [sessions appendFormat:@"newterm-%ld\n", (long)index];
    }
    [sessions writeToFile:@"/var/mobile/.newterm/sessions"
               atomically:YES
                 encoding:NSUTF8StringEncoding
                    error:nil];
}

static NSInteger nt_loadSelectedIndex(void) {
    nt_prepareStateDirectory();
    NSInteger fromFile = nt_readIntegerFile(@"/var/mobile/.newterm/selected-index", 0);
    if (fromFile >= 0) {
        return fromFile;
    }
    return [[NSUserDefaults standardUserDefaults]
        integerForKey:@"NewTermCompatSelectedTabIndex"];
}

static void nt_saveSelectedIndex(NSInteger index) {
    NSInteger clamped = MAX(index, 0);
    [[NSUserDefaults standardUserDefaults] setInteger:clamped
                                                 forKey:@"NewTermCompatSelectedTabIndex"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    nt_prepareStateDirectory();
    nt_writeIntegerFile(@"/var/mobile/.newterm/selected-index", clamped);
}

static void nt_resetLaunchCursor(void) {
    nt_prepareStateDirectory();
    nt_writeIntegerFile(@"/var/mobile/.newterm/launch-cursor", 0);
}

static int nt_nextSessionSlot(void) {
    int fd = open("/var/mobile/.newterm/launch-cursor", O_RDWR | O_CREAT, 0600);
    if (fd < 0) {
        return 1;
    }

    flock(fd, LOCK_EX);
    char buffer[32] = { 0 };
    ssize_t length = pread(fd, buffer, sizeof(buffer) - 1, 0);
    long previous = length > 0 ? strtol(buffer, NULL, 10) : 0;
    if (previous < 0 || previous > 1000) {
        previous = 0;
    }

    long slot = previous + 1;
    char next[32];
    int nextLength = snprintf(next, sizeof(next), "%ld\n", slot);
    ftruncate(fd, 0);
    pwrite(fd, next, (size_t)nextLength, 0);
    flock(fd, LOCK_UN);
    close(fd);
    return (int)slot;
}

static char **nt_environmentWithTmux(char *const environment[]) {
    size_t count = 0;
    if (environment) {
        while (environment[count]) {
            count++;
        }
    }

    static const char *overrides[] = {
        "HOME=/var/mobile",
        "USER=mobile",
        "LOGNAME=mobile",
        "SHELL=/bin/bash",
        "PATH=/var/mobile/bin:/var/mobile/.codex/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "TERM=xterm-256color",
        "LANG=en_US.UTF-8",
        "LC_CTYPE=en_US.UTF-8",
        "LC_TERMINAL=NewTerm",
        "TERM_PROGRAM=NewTerm",
        "COLORTERM=truecolor",
        "CODEX_HOME=/var/mobile/.codex",
        "TMUX_TMPDIR=/var/mobile/.newterm/tmp"
    };
    const size_t overrideCount = sizeof(overrides) / sizeof(overrides[0]);
    char **copy = calloc(count + overrideCount + 1, sizeof(char *));
    if (!copy) {
        return NULL;
    }

    for (size_t index = 0; index < count; index++) {
        copy[index] = environment[index];
    }

    for (size_t overrideIndex = 0; overrideIndex < overrideCount; overrideIndex++) {
        const char *override = overrides[overrideIndex];
        const char *equals = strchr(override, '=');
        size_t nameLength = equals ? (size_t)(equals - override) : strlen(override);
        BOOL replaced = NO;
        for (size_t index = 0; index < count; index++) {
            if (strncmp(copy[index], override, nameLength) == 0 && copy[index][nameLength] == '=') {
                copy[index] = (char *)override;
                replaced = YES;
                break;
            }
        }
        if (!replaced) {
            copy[count++] = (char *)override;
        }
    }
    copy[count] = NULL;
    return copy;
}

static int nt_execve(const char *path, char *const arguments[], char *const environment[]) {
    if (originalExecve && path &&
        (strcmp(path, "/usr/bin/login") == 0 || strcmp(path, "/bin/bash") == 0)) {
        // Direct mode deliberately keeps NewTerm's normal login path. The
        // previous tmux hook replaced login with bash, which bypassed login's
        // passwd lookup and left HOME unset. That is why Codex reported that
        // it could not find its home directory.
        char **directEnvironment = nt_environmentWithTmux(environment);
        int result = originalExecve(path, arguments, directEnvironment);
        int savedError = errno;
        free(directEnvironment);
        errno = savedError;
        return result;
    }

    return originalExecve ? originalExecve(path, arguments, environment) : -1;
}

static void nt_restoreTabs(id root) {
    if (!root || objc_getAssociatedObject(root, nt_restoredRootKey)) {
        return;
    }
    objc_setAssociatedObject(root, nt_restoredRootKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSInteger targetCount = nt_clampedTabCount(nt_launchTabCount);
    NSArray *terminals = nil;
    @try {
        terminals = [root valueForKey:@"terminals"];
    } @catch (__unused NSException *exception) {
        terminals = nil;
    }
    NSInteger currentCount = terminals.count;

    nt_restoringTabs = YES;
    while (currentCount < targetCount && originalRootAddTerminal) {
        originalRootAddTerminal(root, sel_registerName("addTerminal"));
        currentCount++;
    }

    NSInteger selectedIndex = MIN(MAX(nt_loadSelectedIndex(), 0), MAX(currentCount - 1, 0));
    if (originalRootSelectTerminalAtIndex && currentCount > 0) {
        originalRootSelectTerminalAtIndex(root,
                                          sel_registerName("selectTerminalAtIndex:"),
                                          selectedIndex);
    }
    nt_restoringTabs = NO;
}

static void nt_rootLoadView(id self, SEL selector) {
    nt_restoringTabs = YES;
    originalRootLoadView(self, selector);
    nt_restoringTabs = NO;

    __weak id weakRoot = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        nt_restoreTabs(weakRoot);
    });
}

static void nt_rootAddTerminal(id self, SEL selector) {
    originalRootAddTerminal(self, selector);
    if (!nt_restoringTabs) {
        nt_saveTabCount(nt_loadTabCount() + 1);
        nt_saveSelectedIndex(nt_loadTabCount() - 1);
    }
}

static void nt_rootRemoveCurrentTerminal(id self, SEL selector) {
    originalRootRemoveCurrentTerminal(self, selector);
    if (!nt_restoringTabs) {
        nt_saveTabCount(nt_loadTabCount() - 1);
        nt_saveSelectedIndex(0);
    }
}

static void nt_rootRemoveAllTerminals(id self, SEL selector) {
    originalRootRemoveAllTerminals(self, selector);
    if (!nt_restoringTabs) {
        nt_saveTabCount(1);
        nt_saveSelectedIndex(0);
    }
}

static void nt_rootSelectTerminalAtIndex(id self, SEL selector, NSInteger index) {
    originalRootSelectTerminalAtIndex(self, selector, index);
    if (!nt_restoringTabs) {
        nt_saveSelectedIndex(index);
    }
}

// NewTerm 2.5 parses subprocess output off the main thread while its 60 Hz UI
// timer walks raw pointers into the same VT100 screen buffer. VT100Screen has
// an internal mutation lock, but VT100StringSupplier does not hold that lock
// while creating its snapshot. Serialize the complete mutation/snapshot paths
// here. This must be recursive because controller resize and UI refresh calls
// re-enter hooks below.
static pthread_mutex_t terminalMutex;
static const void *lastRenderedAtKey = &lastRenderedAtKey;

// NewTerm 2.5's -[VT100Screen setString:ascii:] advances _cursorX and marks
// the new cursor dirty before checking whether the cursor wrapped. On the
// bottom-right cell this writes _dirty[width * height], one byte beyond the
// allocation made by VT100Screen. Keep a small canary area after the legacy
// allocation so that known write cannot corrupt malloc metadata. The original
// owner still frees this pointer normally.
static void nt_padDirtyBuffer(id screen, int width, int height) {
    if (width <= 0 || height <= 0 || width >= 400 || height > 1000) {
        return;
    }

    Ivar dirtyIvar = class_getInstanceVariable([screen class], "_dirty");
    if (!dirtyIvar) {
        return;
    }

    size_t cellCount = (size_t)width * (size_t)height;
    const size_t guardSize = 64;
    uint8_t *objectBytes = (uint8_t *)(__bridge void *)screen;
    char **dirtySlot = (char **)(objectBytes + ivar_getOffset(dirtyIvar));
    if (!*dirtySlot) {
        return;
    }

    char *padded = (char *)realloc(*dirtySlot, cellCount + guardSize);
    if (padded) {
        memset(padded + cellCount, 0, guardSize);
        *dirtySlot = padded;
    }
}

static bool nt_isValidSize(unsigned int width, unsigned int height) {
    // VT100Screen uses a fixed 400-cell row scratch buffer. The SE's usable
    // grid is far below these limits; larger values indicate wrapped/invalid
    // keyboard-layout geometry from the old Swift UI layer.
    return width >= 10 && width < 400 && height >= 3 && height <= 1000;
}

static id nt_sendObject(id target, const char *selectorName) {
    if (!target) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(target, sel_registerName(selectorName));
}

static UIColor *nt_colorAtIndex(id colorMap, unsigned int index, NSMutableDictionary *cache) {
    NSNumber *key = @(index);
    UIColor *color = cache[key];
    if (!color) {
        unsigned int styleBits = index & (BOLD_MASK | UNDER_MASK | BLINK_MASK);
        unsigned int baseIndex = index & ~styleBits;
        if ((styleBits & BOLD_MASK) && baseIndex == FG_COLOR_CODE) {
            color = nt_sendObject(colorMap, "foregroundBold");
        } else {
            color = ((id (*)(id, SEL, unsigned int))objc_msgSend)(
            colorMap,
            sel_registerName("colorAtIndex:"),
                baseIndex
            );
        }
        if (color) {
            cache[key] = color;
        }
    }
    return color;
}

static NSString *nt_stringForScreenChar(screen_char_t *character) {
    if (!character || character->code == 0 ||
        (character->code >= ITERM2_PRIVATE_BEGIN &&
         character->code <= ITERM2_PRIVATE_END)) {
        return @" ";
    }

    // NewTerm 2.5's VT100Screen predates the extra iTerm screen_char_t
    // metadata fields in the bundled headers. Its parser initializes code,
    // foregroundColor, and backgroundColor, but leaves complexChar and the
    // other bitfields untouched. Trusting complexChar therefore makes random
    // ASCII cells look like keys into the complex-character table; a failed
    // lookup turns an otherwise valid letter into a blank glyph. Render the
    // UTF-16 code unit directly, matching NewTerm's stock string supplier.
    // Adjacent surrogate pairs and combining marks remain intact when the
    // per-cell strings are appended to the complete line.
    unichar code = character->code;
    return [NSString stringWithCharacters:&code length:1];
}

static bool nt_screenAttributesEqual(screen_char_t left, screen_char_t right) {
    return left.foregroundColor == right.foregroundColor &&
        left.backgroundColor == right.backgroundColor;
}

static NSMutableDictionary *nt_attributesForScreenChar(
    screen_char_t character,
    id colorMap,
    id fontMetrics,
    NSMutableDictionary *foregroundCache,
    NSMutableDictionary *backgroundCache
) {
    UIColor *foreground = nt_colorAtIndex(colorMap, character.foregroundColor, foregroundCache);
    UIColor *background = nt_colorAtIndex(colorMap, character.backgroundColor, backgroundCache);
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithCapacity:4];
    if (foreground) {
        attributes[NSForegroundColorAttributeName] = foreground;
    }
    if (background) {
        attributes[NSBackgroundColorAttributeName] = background;
    }
    if ((character.foregroundColor & BOLD_MASK) != 0) {
        UIFont *boldFont = nt_sendObject(fontMetrics, "boldFont");
        if (boldFont) {
            attributes[NSFontAttributeName] = boldFont;
        }
    }
    // The stock iOS 13 renderer intentionally does not apply ANSI underline.
    // TextKit on this old device draws some underlined runs like literal
    // underscore fragments, which makes Codex paths and error messages look
    // corrupted even though the terminal buffer is correct.
    return attributes;
}

static void nt_setScreenSize(id self, SEL selector, NTScreenSize size) {
    if (!nt_isValidSize(size.width, size.height)) {
        return;
    }

    pthread_mutex_lock(&terminalMutex);
    @try {
        NTScreenSize current = ((NTScreenSize (*)(id, SEL))objc_msgSend)(self, sel_registerName("screenSize"));
        if (current.width != size.width || current.height != size.height) {
            originalSetScreenSize(self, selector, size);
        }
    } @finally {
        pthread_mutex_unlock(&terminalMutex);
    }
}

static void nt_resize(id self, SEL selector, int width, int height) {
    if (width < 0 || height < 0 || !nt_isValidSize((unsigned int)width, (unsigned int)height)) {
        return;
    }

    // The original implementation checks for duplicates before acquiring its
    // own screen lock. Serialize before that check so simultaneous keyboard
    // and layout notifications cannot both resize the same backing buffer.
    pthread_mutex_lock(&terminalMutex);
    @try {
        int currentWidth = ((int (*)(id, SEL))objc_msgSend)(self, sel_registerName("width"));
        int currentHeight = ((int (*)(id, SEL))objc_msgSend)(self, sel_registerName("height"));
        if (currentWidth != width || currentHeight != height) {
            originalResize(self, selector, width, height);
            nt_padDirtyBuffer(self, width, height);
        }
    } @finally {
        pthread_mutex_unlock(&terminalMutex);
    }
}

static void nt_initScreen(id self, SEL selector, int width, int height) {
    // Keep enough native scrollback for long Codex sessions. The fast renderer
    // below makes this practical; the stock renderer performs one attributed-
    // string mutation per character and becomes unusable at this depth.
    ((void (*)(id, SEL, unsigned int))objc_msgSend)(
        self,
        sel_registerName("setMaxScrollbackLines:"),
        10000
    );
    originalInitScreen(self, selector, width, height);
    nt_padDirtyBuffer(self, width, height);
}

static void nt_readInputStream(id self, SEL selector, NSData *data) {
    if (data.length == 0) {
        return;
    }

    // SubProcess delivers dispatch-I/O reads away from the main thread in
    // NewTerm 2.5. The legacy terminal also exposes several unguarded screen
    // getters to UIKit, so a mutex around only the parser and renderer is not
    // sufficient. Marshal every mutation onto the main queue instead. NSData
    // and the terminal are retained by the block under ARC, and FIFO dispatch
    // preserves the byte-stream order from the serial dispatch-I/O callback.
    if (![NSThread isMainThread]) {
        NSData *capturedData = [data copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            @autoreleasepool {
                nt_readInputStream(self, selector, capturedData);
            }
        });
        return;
    }

    pthread_mutex_lock(&terminalMutex);
    @try {
        originalReadInputStream(self, selector, data);
    } @finally {
        pthread_mutex_unlock(&terminalMutex);
    }
}

static void nt_clearScreen(id self, SEL selector) {
    pthread_mutex_lock(&terminalMutex);
    @try {
        originalClearScreen(self, selector);
    } @finally {
        pthread_mutex_unlock(&terminalMutex);
    }
}

static id nt_attributedString(id self, SEL selector) {
    id result = nil;
    pthread_mutex_lock(&terminalMutex);
    @try {
        id<ScreenBuffer> screenBuffer = nt_sendObject(self, "screenBuffer");
        id fontMetrics = nt_sendObject(self, "fontMetrics");
        id colorMap = nt_sendObject(self, "colorMap");
        UIFont *regularFont = nt_sendObject(fontMetrics, "regularFont");
        UIColor *defaultForeground = nt_sendObject(colorMap, "foreground");
        UIColor *defaultBackground = nt_sendObject(colorMap, "background");

        int rowCount = [screenBuffer numberOfRows];
        ScreenSize screenSize = [screenBuffer screenSize];
        int width = (int)screenSize.width;
        if (!screenBuffer || !regularFont || !colorMap || rowCount <= 0 ||
            rowCount > 11000 || !nt_isValidSize((unsigned int)width, screenSize.height)) {
            result = [originalAttributedString(self, selector) copy];
        } else {
            NSMutableString *plainText = [[NSMutableString alloc]
                initWithCapacity:(NSUInteger)rowCount * (NSUInteger)(width + 1)];
            NSUInteger *rowOffsets = calloc((size_t)rowCount, sizeof(*rowOffsets));
            NSUInteger *cellOffsets = calloc(
                (size_t)rowCount * (size_t)width,
                sizeof(*cellOffsets)
            );

            if (!rowOffsets || !cellOffsets) {
                free(rowOffsets);
                free(cellOffsets);
                result = [originalAttributedString(self, selector) copy];
            } else {
                for (int rowIndex = 0; rowIndex < rowCount; rowIndex++) {
                    screen_char_t *row = [screenBuffer bufferForRow:rowIndex];
                    rowOffsets[rowIndex] = plainText.length;
                    for (int column = 0; column < width; column++) {
                        NSUInteger offset = (size_t)rowIndex * (size_t)width + (size_t)column;
                        cellOffsets[offset] = plainText.length;
                        [plainText appendString:nt_stringForScreenChar(row ? row + column : NULL)];
                    }
                    if (rowIndex != rowCount - 1) {
                        [plainText appendString:@"\n"];
                    }
                }

                NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
                paragraphStyle.alignment = NSTextAlignmentLeft;
                paragraphStyle.baseWritingDirection = NSWritingDirectionLeftToRight;
                paragraphStyle.lineBreakMode = NSLineBreakByClipping;

                NSMutableDictionary *baseAttributes = [@{
                    NSFontAttributeName: regularFont,
                    NSParagraphStyleAttributeName: paragraphStyle
                } mutableCopy];
                if (defaultForeground) {
                    baseAttributes[NSForegroundColorAttributeName] = defaultForeground;
                }
                if (defaultBackground) {
                    baseAttributes[NSBackgroundColorAttributeName] = defaultBackground;
                }

                NSMutableAttributedString *attributed =
                    [[NSMutableAttributedString alloc] initWithString:plainText
                                                               attributes:baseAttributes];
                NSMutableDictionary *foregroundCache = [NSMutableDictionary dictionary];
                NSMutableDictionary *backgroundCache = [NSMutableDictionary dictionary];

                // Preserve ANSI colors and text styles, but coalesce adjacent equal cells into one
                // attributed-string update instead of the stock per-character loop.
                for (int rowIndex = 0; rowIndex < rowCount; rowIndex++) {
                    screen_char_t *row = [screenBuffer bufferForRow:rowIndex];
                    if (!row) {
                        continue;
                    }
                    int runStart = 0;
                    screen_char_t runCharacter = row[0];
                    for (int column = 1; column <= width; column++) {
                        bool finishesRun = column == width ||
                            !nt_screenAttributesEqual(runCharacter, row[column]);
                        if (!finishesRun) {
                            continue;
                        }

                        NSMutableDictionary *runAttributes = nt_attributesForScreenChar(
                            runCharacter,
                            colorMap,
                            fontMetrics,
                            foregroundCache,
                            backgroundCache
                        );
                        NSUInteger rowOffset = rowOffsets[rowIndex];
                        NSUInteger location = cellOffsets[
                            (size_t)rowIndex * (size_t)width + (size_t)runStart
                        ];
                        NSUInteger rowEnd = rowIndex + 1 < rowCount
                            ? rowOffsets[rowIndex + 1] - 1
                            : plainText.length;
                        NSUInteger endLocation = column == width
                            ? rowEnd
                            : cellOffsets[
                                (size_t)rowIndex * (size_t)width + (size_t)column
                            ];
                        [attributed addAttributes:runAttributes
                                           range:NSMakeRange(location, endLocation - location)];

                        if (column < width) {
                            runStart = column;
                            runCharacter = row[column];
                        }
                    }
                }

                ScreenPosition cursor = [screenBuffer cursorPosition];
                if (rowCount > screenSize.height) {
                    cursor.y += (unsigned int)rowCount - (unsigned int)screenSize.height;
                }
                if (cursor.x < (unsigned int)width && cursor.y < (unsigned int)rowCount) {
                    UIColor *cursorForeground = nt_sendObject(colorMap, "foregroundCursor");
                    UIColor *cursorBackground = nt_sendObject(colorMap, "backgroundCursor");
                    NSMutableDictionary *cursorAttributes =
                        [NSMutableDictionary dictionaryWithCapacity:2];
                    if (cursorForeground) {
                        cursorAttributes[NSForegroundColorAttributeName] = cursorForeground;
                    }
                    if (cursorBackground) {
                        cursorAttributes[NSBackgroundColorAttributeName] = cursorBackground;
                    }
                    NSUInteger location = cellOffsets[
                        (size_t)cursor.y * (size_t)width + (size_t)cursor.x
                    ];
                    NSUInteger rowEnd = cursor.y + 1 < (unsigned int)rowCount
                        ? rowOffsets[cursor.y + 1] - 1
                        : plainText.length;
                    NSUInteger endLocation = cursor.x + 1 < (unsigned int)width
                        ? cellOffsets[
                            (size_t)cursor.y * (size_t)width + (size_t)cursor.x + 1
                        ]
                        : rowEnd;
                    [attributed addAttributes:cursorAttributes
                                       range:NSMakeRange(location, endLocation - location)];
                }

                result = [attributed copy];
                free(rowOffsets);
                free(cellOffsets);
            }
        }
    } @finally {
        pthread_mutex_unlock(&terminalMutex);
    }
    return result;
}

static void nt_updateTimerFired(id self, SEL selector) {
    // TextKit rebuilding a full terminal transcript at 60 Hz is costly on an
    // A9/2 GB device. Adapt the redraw rate to retained history depth. Skipped
    // ticks leave NewTerm's isDirty flag set for the next tick.
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    int rows = ((int (*)(id, SEL))objc_msgSend)(self, sel_registerName("numberOfRows"));
    CFTimeInterval minimumInterval = rows <= 512 ? 0.10 :
        (rows <= 2000 ? 0.20 : (rows <= 5000 ? 0.35 : 0.50));
    NSNumber *lastRenderedValue = objc_getAssociatedObject(self, lastRenderedAtKey);
    CFAbsoluteTime lastRenderedAt = lastRenderedValue.doubleValue;
    if (lastRenderedAt != 0 && now - lastRenderedAt < minimumInterval) {
        return;
    }

    pthread_mutex_lock(&terminalMutex);
    @try {
        objc_setAssociatedObject(self, lastRenderedAtKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        @autoreleasepool {
            originalUpdateTimerFired(self, selector);
        }
    } @finally {
        pthread_mutex_unlock(&terminalMutex);
    }
}

__attribute__((constructor))
static void initializeNewTermCompatShim(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"ws.hbang.Terminal"]) {
            return;
        }

        pthread_mutexattr_t attributes;
        pthread_mutexattr_init(&attributes);
        pthread_mutexattr_settype(&attributes, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(&terminalMutex, &attributes);
        pthread_mutexattr_destroy(&attributes);

        // The stock iOS 13 NewTerm bundle deliberately starts with one fresh
        // terminal every time the process is relaunched. Keep the tab layout
        // and tmux allocation cursor outside that process so a force-close can
        // be followed by a real tab restore.
        nt_launchTabCount = nt_loadTabCount();
        nt_saveTabCount(nt_launchTabCount);
        nt_resetLaunchCursor();

        MSHookFunction((void *)execve, (void *)nt_execve, (void **)&originalExecve);

        Class controller = NSClassFromString(@"NewTermCommon.TerminalController");
        Class terminal = NSClassFromString(@"VT100");
        Class screen = NSClassFromString(@"VT100Screen");
        Class stringSupplier = NSClassFromString(@"VT100StringSupplier");
        Class root = NSClassFromString(@"NewTerm.RootViewController");
        if (!root) {
            root = NSClassFromString(@"RootViewController");
        }

        if (controller) {
            MSHookMessageEx(controller, sel_registerName("setScreenSize:"), (IMP)nt_setScreenSize, (IMP *)&originalSetScreenSize);
            MSHookMessageEx(controller, sel_registerName("updateTimerFired"), (IMP)nt_updateTimerFired, (IMP *)&originalUpdateTimerFired);
        }
        if (terminal) {
            MSHookMessageEx(terminal, sel_registerName("readInputStream:"), (IMP)nt_readInputStream, (IMP *)&originalReadInputStream);
            MSHookMessageEx(terminal, sel_registerName("clearScreen"), (IMP)nt_clearScreen, (IMP *)&originalClearScreen);
        }
        if (screen) {
            MSHookMessageEx(screen, sel_registerName("initScreenWithWidth:Height:"), (IMP)nt_initScreen, (IMP *)&originalInitScreen);
            MSHookMessageEx(screen, sel_registerName("resizeWidth:height:"), (IMP)nt_resize, (IMP *)&originalResize);
        }
        if (stringSupplier) {
            MSHookMessageEx(stringSupplier, sel_registerName("attributedString"), (IMP)nt_attributedString, (IMP *)&originalAttributedString);
        }
        if (root) {
            SEL loadView = sel_registerName("loadView");
            SEL addTerminal = sel_registerName("addTerminal");
            SEL removeCurrentTerminal = sel_registerName("removeCurrentTerminal");
            SEL removeAllTerminals = sel_registerName("removeAllTerminals");
            SEL selectTerminalAtIndex = sel_registerName("selectTerminalAtIndex:");

            if (class_getInstanceMethod(root, loadView)) {
                MSHookMessageEx(root, loadView, (IMP)nt_rootLoadView, (IMP *)&originalRootLoadView);
            }
            if (class_getInstanceMethod(root, addTerminal)) {
                MSHookMessageEx(root, addTerminal, (IMP)nt_rootAddTerminal, (IMP *)&originalRootAddTerminal);
            }
            if (class_getInstanceMethod(root, removeCurrentTerminal)) {
                MSHookMessageEx(root, removeCurrentTerminal, (IMP)nt_rootRemoveCurrentTerminal, (IMP *)&originalRootRemoveCurrentTerminal);
            }
            if (class_getInstanceMethod(root, removeAllTerminals)) {
                MSHookMessageEx(root, removeAllTerminals, (IMP)nt_rootRemoveAllTerminals, (IMP *)&originalRootRemoveAllTerminals);
            }
            if (class_getInstanceMethod(root, selectTerminalAtIndex)) {
                MSHookMessageEx(root, selectTerminalAtIndex, (IMP)nt_rootSelectTerminalAtIndex, (IMP *)&originalRootSelectTerminalAtIndex);
            }
        }
    }
}
