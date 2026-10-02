#include "sfsymbolprovider.h"

#include <QPainter>

#import <AppKit/AppKit.h>

QImage twilightRenderSfSymbol(const QString& name, int pointSize, const QColor& color)
{
    @autoreleasepool {
        if (@available(macOS 11.0, *)) {
            NSString* symbolName = name.toNSString();
            NSImage* base = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:symbolName];
            if (base == nil) {
                return QImage();
            }

            NSImageSymbolConfiguration* config =
                [NSImageSymbolConfiguration configurationWithPointSize:pointSize
                                                                weight:NSFontWeightMedium
                                                                 scale:NSImageSymbolScaleMedium];
            NSImage* image = [base imageWithSymbolConfiguration:config];
            if (image == nil) {
                image = base;
            }

            NSSize symbolSize = image.size;
            if (symbolSize.width < 1.0 || symbolSize.height < 1.0) {
                symbolSize = NSMakeSize(static_cast<CGFloat>(pointSize), static_cast<CGFloat>(pointSize));
            }
            const CGFloat scale = 2.0;
            const int width = qMax(1, static_cast<int>(qRound(symbolSize.width * scale)));
            const int height = qMax(1, static_cast<int>(qRound(symbolSize.height * scale)));

            QImage bitmap(width, height, QImage::Format_ARGB32_Premultiplied);
            bitmap.fill(Qt::transparent);

            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            CGContextRef ctx = CGBitmapContextCreate(bitmap.bits(),
                                                      static_cast<size_t>(width),
                                                      static_cast<size_t>(height),
                                                      8,
                                                      static_cast<size_t>(bitmap.bytesPerLine()),
                                                      space,
                                                      kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
            if (ctx != nullptr) {
                NSGraphicsContext* gc = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:YES];
                [NSGraphicsContext saveGraphicsState];
                [NSGraphicsContext setCurrentContext:gc];
                [image drawInRect:NSMakeRect(0, 0, width, height)];
                [NSGraphicsContext restoreGraphicsState];
                CGContextRelease(ctx);
            }
            CGColorSpaceRelease(space);

            QPainter painter(&bitmap);
            painter.setCompositionMode(QPainter::CompositionMode_SourceIn);
            painter.fillRect(bitmap.rect(), color);
            painter.end();
            return bitmap;
        }
    }
    return QImage();
}
