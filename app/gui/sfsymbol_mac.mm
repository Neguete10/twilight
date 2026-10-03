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

            const int glyphWidth = qMax(1, static_cast<int>(CGImageGetWidth(cgImage)));
            const int glyphHeight = qMax(1, static_cast<int>(CGImageGetHeight(cgImage)));
            // Square slot so a wide or tall symbol stays optically centered.
            const int side = qMax(glyphWidth, glyphHeight);
            const CGFloat originX = (side - glyphWidth) / 2.0;
            const CGFloat originY = (side - glyphHeight) / 2.0;

            QImage bitmap(side, side, QImage::Format_ARGB32_Premultiplied);
            bitmap.fill(Qt::transparent);

            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            CGContextRef ctx = CGBitmapContextCreate(bitmap.bits(),
                                                      static_cast<size_t>(side),
                                                      static_cast<size_t>(side),
                                                      8,
                                                      static_cast<size_t>(bitmap.bytesPerLine()),
                                                      space,
                                                      kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
            CGColorSpaceRelease(space);
            if (ctx == nullptr) {
                return QImage();
            }

            // Same recipe as Qt's qt_mac_toQPixmap (qcoregraphics.mm):
            // QMacCGContext flips the CTM so y grows down from the top row,
            // then NSImage is drawn with respectFlipped:YES.
            //
            // The previous attempt flipped the CTM and called CGContextDrawImage.
            // That helper exists only to undo a flipped context (qt_mac_drawCGImage
            // flips *again* before CGContextDrawImage). One flip plus
            // CGContextDrawImage leaves the glyph upside down, which is what
            // the Mac build still showed. drawInRect: without respectFlipped
            // also ignored the flipped flag, so the first attempt was inverted too.
            CGContextTranslateCTM(ctx, 0, side);
            CGContextScaleCTM(ctx, 1, -1);
            NSGraphicsContext* gc = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:YES];
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext:gc];
            [image drawInRect:NSMakeRect(originX, originY, glyphWidth, glyphHeight)
                     fromRect:NSZeroRect
                    operation:NSCompositingOperationSourceOver
                     fraction:1.0
               respectFlipped:YES
                        hints:nil];
            [NSGraphicsContext restoreGraphicsState];
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
