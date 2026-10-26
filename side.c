// 마우스 옆 버튼 경계: 맥 이벤트 탭으로 3·4번 버튼을 가로채고, 키 입력을 보내고, 메뉴 막대 아이콘을 띄운다.
// 버튼을 어떤 동작으로 바꿀지는 back.bend 가 정한다.
// 이 파일에 #import 가 있으면 bend 는 맥에서 Objective-C(-fobjc-arc -fmodules)로 컴파일하고 프레임워크를 링크한다.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <ServiceManagement/ServiceManagement.h>
#include <fcntl.h>
#include <mach-o/dyld.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>

extern char** environ;

#define SIDE_QUIT -1

// 탭과 메뉴가 넣고 SideButton.wait 가 꺼내는 줄. 모두 주 스레드에서만 만진다.
static int side_q[64];
static unsigned side_head = 0, side_tail = 0;
static CFMachPortRef side_tap = NULL;
static NSStatusItem* side_icon = nil;
static NSMenuItem* side_status = nil;

static void side_push(int v) {
  if (side_tail - side_head < 64) side_q[side_tail++ % 64] = v;
}

@interface BendBackMenu : NSObject
@end
@implementation BendBackMenu
- (void)quit:(id)sender { side_push(SIDE_QUIT); }
@end
static BendBackMenu* side_menu = nil;

static void side_say(NSString* s) {
  side_status.title = s;
  fprintf(stderr, "%s\n", s.UTF8String);
}

// 메뉴 막대 아이콘: 상태 한 줄과 종료. Dock 아이콘은 두지 않는다(Info.plist 의 LSUIElement).
static void side_ui(void) {
  [NSApplication sharedApplication];
  [NSApp finishLaunching];
  side_icon = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
  NSImage* img = [NSImage imageWithSystemSymbolName:@"computermouse" accessibilityDescription:@"BendBack"];
  img.template = YES;
  side_icon.button.image = img;
  side_menu = [BendBackMenu new];
  NSMenu* menu = [NSMenu new];
  side_status = [[NSMenuItem alloc] initWithTitle:@"작동 중" action:nil keyEquivalent:@""];
  NSMenuItem* quit = [[NSMenuItem alloc] initWithTitle:@"종료" action:@selector(quit:) keyEquivalent:@""];
  quit.target = side_menu;
  [menu addItem:side_status];
  [menu addItem:NSMenuItem.separatorItem];
  [menu addItem:quit];
  side_icon.menu = menu;
}

// 줄에 무엇이 들어오거나 secs 초가 지날 때까지 주 스레드에서 맥 이벤트를 돌린다(Base window.c 의 window_wait 과 같은 방식).
// 탭의 mach port 도 이 실행 루프에 있어서, 버튼이 오면 runMode 가 돌아온다.
static void side_pump(NSTimeInterval secs) {
  NSDate* until = [NSDate dateWithTimeIntervalSinceNow:secs];
  while (side_head == side_tail) {
    @autoreleasepool {
      NSEvent* ev = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:NSDate.distantPast
                                          inMode:NSDefaultRunLoopMode dequeue:YES];
      if (ev) {
        [NSApp sendEvent:ev];
        continue;
      }
      if (until.timeIntervalSinceNow <= 0) return;
      [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:until];
    }
  }
}

// 눌림만 줄에 넣고, 3·4번은 떼기까지 삼켜 앱이 원래 신호를 따로 받지 않게 한다.
static CGEventRef side_cb(CGEventTapProxy p, CGEventType t, CGEventRef ev, void* u) {
  if (t == kCGEventTapDisabledByTimeout || t == kCGEventTapDisabledByUserInput) {
    CGEventTapEnable(side_tap, true);
    return ev;
  }
  int64_t b = CGEventGetIntegerValueField(ev, kCGMouseEventButtonNumber);
  if (b < 3) return ev;
  if (t == kCGEventOtherMouseDown) side_push(b > 255 ? 255 : (int)b);
  return (b == 3 || b == 4) ? NULL : ev;
}

// 맥은 떠 있는 프로세스의 손쉬운 사용 판정을 갱신하지 않는다. 자기 자신을 --trusted 로 새로 띄워 물으면 새 판정이 나온다.
static bool side_trusted_now(void) {
  char path[PATH_MAX];
  uint32_t n = sizeof path;
  if (_NSGetExecutablePath(path, &n) != 0) return false;
  char* argv[] = {path, "--trusted", NULL};
  pid_t pid;
  int st;
  if (posix_spawn(&pid, path, NULL, NULL, argv, environ) != 0) return false;
  return waitpid(pid, &st, 0) == pid && WIFEXITED(st) && WEXITSTATUS(st) == 0;
}

// 이 프로세스가 끝난 뒤 앱을 새로 연다. 새 프로세스는 허용된 권한으로 탭을 연다.
static void side_relaunch(void) {
  char* argv[] = {"/bin/sh", "-c", "sleep 1; /usr/bin/open -n \"$0\"",
                  (char*)NSBundle.mainBundle.bundlePath.fileSystemRepresentation, NULL};
  pid_t pid;
  posix_spawn(&pid, "/bin/sh", NULL, NULL, argv, environ);
  exit(0);
}

// /Applications 에서 처음 실행할 때 한 번만 로그인 항목으로 등록한다. 사용자가 시스템 설정에서 끄면 그대로 둔다.
static void side_login_item(void) {
  NSUserDefaults* d = NSUserDefaults.standardUserDefaults;
  if (![NSBundle.mainBundle.bundlePath hasPrefix:@"/Applications/"] || [d boolForKey:@"loginItemRegistered"]) return;
  NSError* err = nil;
  if ([SMAppService.mainAppService registerAndReturnError:&err]) [d setBool:YES forKey:@"loginItemRegistered"];
  else fprintf(stderr, "로그인 항목 등록 실패: %s\n", err.localizedDescription.UTF8String);
}

// 처음 부를 때 아이콘과 탭을 연다. 권한이 없으면 묻는 창을 띄우고, 허용될 때까지 기다렸다가 다시 시작한다.
static Term side_open(Env e) {
  side_ui();
  NSString* bid = NSBundle.mainBundle.bundleIdentifier;
  if (bid && [NSRunningApplication runningApplicationsWithBundleIdentifier:bid].count > 1) {
    fprintf(stderr, "이미 실행 중이라 끝냅니다\n");
    exit(0);
  }
  side_login_item();
  if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString*)kAXTrustedCheckOptionPrompt: @YES})) {
    side_say(@"권한 필요");
    while (!side_trusted_now()) {
      side_pump(2);
      if (side_head != side_tail) return 0;
    }
    side_relaunch();
  }
  CGEventMask m = CGEventMaskBit(kCGEventOtherMouseDown) | CGEventMaskBit(kCGEventOtherMouseUp);
  side_tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, m, side_cb, NULL);
  if (!side_tap) return io_fail(e, EPERM, "이벤트 탭을 열지 못했습니다");
  CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(NULL, side_tap, 0);
  CFRunLoopAddSource(CFRunLoopGetMain(), src, kCFRunLoopCommonModes);
  side_say(@"작동 중");
  return 0;
}

Term sidebutton_wait_run(Env e, Term* f, IoWork* w) {
  static bool opened = false;
  if (!opened) {
    opened = true;
    Term fail = side_open(e);
    if (fail) return fail;
  }
  while (side_head == side_tail) side_pump(1e9);
  int v = side_q[side_head++ % 64];
  // U32 칸 하나뿐인 생성자는 컴파일러가 힙 없이 한 단어로 담는다(term_pak).
  return io_done(e, v == SIDE_QUIT ? term_pak(CID(Quit), 0) : term_pak(CID(Press), (uint32_t)v));
}

static void side_key(CGKeyCode code, bool down, CGEventFlags flags) {
  CGEventRef k = CGEventCreateKeyboardEvent(NULL, code, down);
  CGEventSetFlags(k, flags);
  CGEventPost(kCGSessionEventTap, k);
  CFRelease(k);
}

// ⌘ 표시만 붙이면 Finder 가 ⌘] 를 무시할 때가 있어(시험에서 0/5), ⌘ 키(55)를 실제로 눌렀다 뗀다(5/5).
Term keys_tap_run(Env e, Term* f, IoWork* w) {
  CGKeyCode code = (CGKeyCode)(uint32_t)f[0];
  CGEventFlags flags = (CGEventFlags)(uint32_t)f[1];
  bool cmd = flags & kCGEventFlagMaskCommand;
  if (cmd) side_key(55 /* kVK_Command */, true, kCGEventFlagMaskCommand);
  side_key(code, true, flags);
  side_key(code, false, flags);
  if (cmd) side_key(55 /* kVK_Command */, false, 0);
  return term_pak(CID(Unit), 0);
}

// 터미널이 아니면(Finder·로그인 항목으로 켜졌으면) stderr 를 로그 파일로 보낸다. 1MB 를 넘으면 새로 쓴다.
static void side_log(void) {
  if (isatty(2)) return;
  NSString* path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/BendBack.log"];
  struct stat s;
  bool big = stat(path.fileSystemRepresentation, &s) == 0 && s.st_size > (1 << 20);
  int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | (big ? O_TRUNC : O_APPEND), 0644);
  if (fd >= 0) {
    dup2(fd, 2);
    close(fd);
  }
}

static void __attribute__((constructor)) side_use(int argc, char** argv) {
  if (argc > 1 && strcmp(argv[1], "--trusted") == 0) exit(AXIsProcessTrusted() ? 0 : 1);
  side_log();
#ifdef CID(SideButton.wait)
  io_eff(CID(SideButton.wait), sidebutton_wait_run);
#endif
#ifdef CID(Keys.tap)
  io_eff(CID(Keys.tap), keys_tap_run);
#endif
}
