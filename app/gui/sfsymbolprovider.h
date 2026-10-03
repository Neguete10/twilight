#pragma once

#include <QColor>
#include <QImage>
#include <QQuickImageProvider>
#include <QSize>
#include <QString>

// macOS 11+ draws real SF Symbols through NSImage. Every other platform, and
// any name AppKit does not recognize, gets a small geometric stand-in so the
// shell still has icons. See docs/TWILIGHT_UI_V2.md.
QImage twilightRenderSfSymbol(const QString& name, int pointSize, const QColor& color);
QImage twilightDrawFallbackSymbol(const QString& name, int pixelSize, const QColor& color);

class SfSymbolImageProvider : public QQuickImageProvider
{
public:
    SfSymbolImageProvider();

    QImage requestImage(const QString& id, QSize* size, const QSize& requestedSize) override;
};
