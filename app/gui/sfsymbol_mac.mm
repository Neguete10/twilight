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
            NSRect proposed = NSMakeRect(0, 0, symbolSize.width * scale, symbolSize.height * scale);
            CGImageRef cgImage = [image CGImageForProposedRect:&proposed context:nil hints:nil];
            if (cgImage == nil) {
                return QImage();
            }

            const int width = qMax(1, static_cast<int>(CGImageGetWidth(cgImage)));
            const int height = qMax(1, static_cast<int>(CGImageGetHeight(cgImage)));

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
            CGColorSpaceRelease(space);
            if (ctx == nullptr) {
                return QImage();
            }

            // A CGBitmapContext treats the first QImage row as the bottom.
            // Flip the context once so every SF Symbol lands right-side up.
            // drawInRect: ignored NSGraphicsContext's flipped flag, which is
            // why wifi, pencil, trash, display, gamecontroller, and network
            // (and the other glyphs) were inverted together.
            CGContextTranslateCTM(ctx, 0, height);
            CGContextScaleCTM(ctx, 1, -1);
            CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), cgImage);
            CGContextRelease(ctx);

            QPainter painter(&bitmap);
            painter.setCompositionMode(QPainter::CompositionMode_SourceIn);
            painter.fillRect(bitmap.rect(), color);
            painter.end();
            return bitmap;
        }
    }
    return QImage();
}
