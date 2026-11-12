// Private AppKit class methods for "system modal" Touch Bars.
// These are the same calls Pock, MTMR and XTouchBar use (see ../XTouchBar-master).
// They only change what the Touch Bar *shows*; nothing is written to disk and
// the normal Touch Bar comes back as soon as this app dismisses its bar or quits.

#import <AppKit/AppKit.h>

@interface NSTouchBar (BlackoutPrivate)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar
                         placement:(long long)placement
          systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)touchBar;
@end
