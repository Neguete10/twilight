#include "sfsymbolprovider.h"

#include <QPainter>
#include <QStringList>

#include <cmath>

#ifndef TWILIGHT_HAS_SF_SYMBOLS
QImage twilightRenderSfSymbol(const QString&, int, const QColor&)
{
    return QImage();
}
#endif

namespace {

void useFill(QPainter& painter, const QColor& color)
{
    painter.setPen(Qt::NoPen);
    painter.setBrush(color);
}

void useStroke(QPainter& painter, const QColor& color, qreal width)
{
    painter.setBrush(Qt::NoBrush);
    painter.setPen(QPen(color, width, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
}

void drawMoon(QPainter& painter, const QRectF& rect, const QColor& color)
{
    useFill(painter, color);
    painter.drawEllipse(rect);
    painter.setCompositionMode(QPainter::CompositionMode_DestinationOut);
    useFill(painter, Qt::white);
    painter.drawEllipse(rect.translated(rect.width() * 0.34, -rect.height() * 0.06));
    painter.setCompositionMode(QPainter::CompositionMode_SourceOver);
    useFill(painter, color);
    const qreal s = rect.width() * 0.16;
    painter.drawEllipse(QRectF(rect.right() - s, rect.top() + s * 0.2, s, s));
}

void drawStar(QPainter& painter, const QRectF& rect, const QColor& color, bool filled)
{
    QPolygonF poly;
    const QPointF c = rect.center();
    const qreal rx = rect.width() / 2.0;
    const qreal ry = rect.height() / 2.0;
    for (int i = 0; i < 10; ++i) {
        const qreal ang = -3.14159265 / 2.0 + i * 3.14159265 / 5.0;
        const qreal mag = (i % 2 == 0) ? 1.0 : 0.42;
        poly << QPointF(c.x() + std::cos(ang) * rx * mag, c.y() + std::sin(ang) * ry * mag);
    }
    if (filled) {
        useFill(painter, color);
        painter.drawPolygon(poly);
    }
    else {
        useStroke(painter, color, qMax(1.25, rect.width() * 0.08));
        painter.drawPolygon(poly);
    }
}

void drawPlay(QPainter& painter, const QRectF& rect, const QColor& color)
{
    QPolygonF tri;
    tri << QPointF(rect.left(), rect.top())
        << QPointF(rect.right(), rect.center().y())
        << QPointF(rect.left(), rect.bottom());
    useFill(painter, color);
    painter.drawPolygon(tri);
}

void drawDisplay(QPainter& painter, const QRectF& rect, const QColor& color)
{
    useStroke(painter, color, qMax(1.4, rect.width() * 0.07));
    const QRectF screen(rect.left(), rect.top(), rect.width(), rect.height() * 0.72);
    painter.drawRoundedRect(screen, rect.width() * 0.1, rect.width() * 0.1);
    const qreal cx = rect.center().x();
    painter.drawLine(QPointF(cx, screen.bottom()), QPointF(cx, rect.bottom() - rect.height() * 0.06));
    painter.drawLine(QPointF(cx - rect.width() * 0.22, rect.bottom()),
                     QPointF(cx + rect.width() * 0.22, rect.bottom()));
}

void drawSpeaker(QPainter& painter, const QRectF& rect, const QColor& color)
{
    useFill(painter, color);
    const qreal h = rect.height();
    QPolygonF body;
    body << QPointF(rect.left(), rect.top() + h * 0.32)
         << QPointF(rect.left() + rect.width() * 0.28, rect.top() + h * 0.32)
         << QPointF(rect.left() + rect.width() * 0.52, rect.top() + h * 0.08)
         << QPointF(rect.left() + rect.width() * 0.52, rect.top() + h * 0.92)
         << QPointF(rect.left() + rect.width() * 0.28, rect.top() + h * 0.68)
         << QPointF(rect.left(), rect.top() + h * 0.68);
    painter.drawPolygon(body);
    useStroke(painter, color, qMax(1.3, rect.width() * 0.07));
    painter.drawArc(QRectF(rect.left() + rect.width() * 0.48, rect.top() + h * 0.28, rect.width() * 0.28, h * 0.44),
                    -50 * 16, 100 * 16);
    painter.drawArc(QRectF(rect.left() + rect.width() * 0.42, rect.top() + h * 0.12, rect.width() * 0.5, h * 0.76),
                    -50 * 16, 100 * 16);
}

void drawController(QPainter& painter, const QRectF& rect, const QColor& color)
{
    useStroke(painter, color, qMax(1.4, rect.width() * 0.07));
    painter.drawRoundedRect(rect.adjusted(0, rect.height() * 0.18, 0, -rect.height() * 0.08),
                            rect.height() * 0.28, rect.height() * 0.28);
    useFill(painter, color);
    painter.drawEllipse(QRectF(rect.left() + rect.width() * 0.18, rect.center().y() - rect.height() * 0.08,
                               rect.width() * 0.12, rect.width() * 0.12));
    painter.drawEllipse(QRectF(rect.right() - rect.width() * 0.32, rect.center().y() - rect.height() * 0.08,
                               rect.width() * 0.12, rect.width() * 0.12));
}

void drawGear(QPainter& painter, const QRectF& rect, const QColor& color)
{
    painter.save();
    painter.translate(rect.center());
    useFill(painter, color);
    const qreal r = rect.width() / 2.0;
    for (int i = 0; i < 8; ++i) {
        painter.rotate(45);
        painter.drawRoundedRect(QRectF(-r * 0.16, -r, r * 0.32, r * 0.38), r * 0.08, r * 0.08);
    }
    painter.drawEllipse(QRectF(-r * 0.62, -r * 0.62, r * 1.24, r * 1.24));
    painter.setCompositionMode(QPainter::CompositionMode_Clear);
    painter.drawEllipse(QRectF(-r * 0.28, -r * 0.28, r * 0.56, r * 0.56));
    painter.restore();
}

void drawWifi(QPainter& painter, const QRectF& rect, const QColor& color)
{
    useStroke(painter, color, qMax(1.4, rect.width() * 0.08));
    painter.drawArc(rect, 20 * 16, 140 * 16);
    painter.drawArc(rect.adjusted(rect.width() * 0.18, rect.height() * 0.18, -rect.width() * 0.18, -rect.height() * 0.18),
                    20 * 16, 140 * 16);
    useFill(painter, color);
    const qreal d = rect.width() * 0.16;
    painter.drawEllipse(QRectF(rect.center().x() - d / 2.0, rect.bottom() - d, d, d));
}

void drawSliders(QPainter& painter, const QRectF& rect, const QColor& color)
{
    useStroke(painter, color, qMax(1.4, rect.width() * 0.07));
    const qreal xs[3] = {0.2, 0.5, 0.8};
    const qreal ys[3] = {0.35, 0.62, 0.42};
    for (int i = 0; i < 3; ++i) {
        const qreal x = rect.left() + rect.width() * xs[i];
        painter.drawLine(QPointF(x, rect.top()), QPointF(x, rect.bottom()));
        useFill(painter, color);
        const qreal d = rect.width() * 0.16;
        painter.drawEllipse(QRectF(x - d / 2.0, rect.top() + rect.height() * ys[i] - d / 2.0, d, d));
        useStroke(painter, color, qMax(1.4, rect.width() * 0.07));
    }
}

} // namespace

QImage twilightDrawFallbackSymbol(const QString& name, int pixelSize, const QColor& color)
{
    const int size = qMax(16, pixelSize);
    QImage image(size, size, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);

    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing, true);
    const qreal m = size * 0.16;
    const QRectF rect(m, m, size - m * 2.0, size - m * 2.0);
    const qreal stroke = qMax(1.4, size * 0.07);

    if (name == QLatin1String("moon.stars") || name == QLatin1String("moon")) {
        drawMoon(painter, rect.adjusted(0, size * 0.04, -size * 0.12, -size * 0.04), color);
    }
    else if (name == QLatin1String("plus")) {
        useStroke(painter, color, stroke);
        painter.drawLine(QPointF(rect.center().x(), rect.top()), QPointF(rect.center().x(), rect.bottom()));
        painter.drawLine(QPointF(rect.left(), rect.center().y()), QPointF(rect.right(), rect.center().y()));
    }
    else if (name == QLatin1String("magnifyingglass")) {
        useStroke(painter, color, stroke);
        const qreal d = rect.width() * 0.62;
        painter.drawEllipse(QRectF(rect.left(), rect.top(), d, d));
        painter.drawLine(QPointF(rect.left() + d * 0.78, rect.top() + d * 0.78), rect.bottomRight());
    }
    else if (name == QLatin1String("play.fill") || name == QLatin1String("play")) {
        drawPlay(painter, rect.adjusted(size * 0.06, 0, -size * 0.02, 0), color);
    }
    else if (name == QLatin1String("xmark")) {
        useStroke(painter, color, stroke);
        painter.drawLine(rect.topLeft(), rect.bottomRight());
        painter.drawLine(rect.topRight(), rect.bottomLeft());
    }
    else if (name == QLatin1String("gearshape") || name == QLatin1String("gear")) {
        drawGear(painter, rect, color);
    }
    else if (name == QLatin1String("display") || name == QLatin1String("desktopcomputer")) {
        drawDisplay(painter, rect, color);
    }
    else if (name.startsWith(QLatin1String("speaker"))) {
        drawSpeaker(painter, rect, color);
    }
    else if (name == QLatin1String("gamecontroller")) {
        drawController(painter, rect, color);
    }
    else if (name == QLatin1String("network") || name == QLatin1String("wifi")) {
        drawWifi(painter, rect, color);
    }
    else if (name == QLatin1String("star") || name == QLatin1String("star.fill")) {
        drawStar(painter, rect, color, name.endsWith(QLatin1String("fill")));
    }
    else if (name == QLatin1String("checkmark")) {
        useStroke(painter, color, stroke);
        painter.drawLine(QPointF(rect.left(), rect.center().y()),
                         QPointF(rect.left() + rect.width() * 0.35, rect.bottom() - rect.height() * 0.12));
        painter.drawLine(QPointF(rect.left() + rect.width() * 0.35, rect.bottom() - rect.height() * 0.12),
                         rect.topRight());
    }
    else if (name == QLatin1String("slider.horizontal.3")) {
        drawSliders(painter, rect, color);
    }
    else if (name == QLatin1String("trash")) {
        useStroke(painter, color, stroke);
        painter.drawLine(QPointF(rect.left(), rect.top() + rect.height() * 0.18),
                         QPointF(rect.right(), rect.top() + rect.height() * 0.18));
        painter.drawRoundedRect(rect.adjusted(rect.width() * 0.12, rect.height() * 0.22, -rect.width() * 0.12, 0),
                                size * 0.04, size * 0.04);
    }
    else if (name == QLatin1String("pencil")) {
        useStroke(painter, color, stroke);
        painter.drawLine(rect.bottomLeft(), rect.topRight());
        painter.drawLine(rect.bottomLeft(), QPointF(rect.left() + rect.width() * 0.22, rect.bottom()));
    }
    else if (name == QLatin1String("eye") || name == QLatin1String("eye.slash")) {
        useStroke(painter, color, stroke);
        painter.drawArc(rect.adjusted(0, rect.height() * 0.2, 0, -rect.height() * 0.2), 200 * 16, 140 * 16);
        painter.drawArc(rect.adjusted(0, rect.height() * 0.2, 0, -rect.height() * 0.2), 20 * 16, 140 * 16);
        useFill(painter, color);
        painter.drawEllipse(QRectF(rect.center().x() - size * 0.06, rect.center().y() - size * 0.06, size * 0.12, size * 0.12));
        if (name.endsWith(QLatin1String("slash"))) {
            useStroke(painter, color, stroke);
            painter.drawLine(rect.topRight(), rect.bottomLeft());
        }
    }
    else if (name == QLatin1String("arrow.clockwise")) {
        useStroke(painter, color, stroke);
        painter.drawArc(rect, 40 * 16, 280 * 16);
        drawPlay(painter, QRectF(rect.right() - size * 0.22, rect.top(), size * 0.2, size * 0.2), color);
    }
    else if (name == QLatin1String("chevron.left") || name == QLatin1String("chevron.right")) {
        useStroke(painter, color, stroke);
        const bool left = name.endsWith(QLatin1String("left"));
        const QPointF mid = left ? QPointF(rect.left(), rect.center().y()) : QPointF(rect.right(), rect.center().y());
        const QPointF a = left ? rect.topRight() : rect.topLeft();
        const QPointF b = left ? rect.bottomRight() : rect.bottomLeft();
        painter.drawLine(a, mid);
        painter.drawLine(mid, b);
    }
    else if (name == QLatin1String("stop.fill")) {
        useFill(painter, color);
        painter.drawRoundedRect(rect, size * 0.08, size * 0.08);
    }
    else if (name == QLatin1String("power")) {
        useStroke(painter, color, stroke);
        painter.drawArc(rect.adjusted(0, size * 0.12, 0, 0), 50 * 16, 260 * 16);
        painter.drawLine(QPointF(rect.center().x(), rect.top()), QPointF(rect.center().x(), rect.center().y()));
    }
    else if (name == QLatin1String("info.circle")) {
        useStroke(painter, color, stroke);
        painter.drawEllipse(rect);
        useFill(painter, color);
        painter.drawEllipse(QRectF(rect.center().x() - stroke, rect.top() + rect.height() * 0.22, stroke * 2, stroke * 2));
        painter.drawRoundedRect(QRectF(rect.center().x() - stroke * 0.7, rect.top() + rect.height() * 0.4,
                                       stroke * 1.4, rect.height() * 0.36), stroke, stroke);
    }
    else if (name == QLatin1String("exclamationmark.triangle")) {
        QPolygonF tri;
        tri << QPointF(rect.center().x(), rect.top())
            << rect.bottomLeft()
            << rect.bottomRight();
        useStroke(painter, color, stroke);
        painter.drawPolygon(tri);
    }
    else if (name == QLatin1String("bolt.fill") || name == QLatin1String("sparkles")) {
        QPolygonF bolt;
        bolt << QPointF(rect.left() + rect.width() * 0.55, rect.top())
             << QPointF(rect.left() + rect.width() * 0.2, rect.center().y())
             << QPointF(rect.center().x(), rect.center().y())
             << QPointF(rect.left() + rect.width() * 0.4, rect.bottom())
             << QPointF(rect.right(), rect.center().y() - rect.height() * 0.08)
             << QPointF(rect.center().x() + rect.width() * 0.05, rect.center().y() - rect.height() * 0.08);
        useFill(painter, color);
        painter.drawPolygon(bolt);
    }
    else if (name == QLatin1String("ellipsis")) {
        useFill(painter, color);
        const qreal d = size * 0.12;
        for (int i = 0; i < 3; ++i) {
            const qreal x = rect.left() + rect.width() * (0.15 + i * 0.35);
            painter.drawEllipse(QRectF(x, rect.center().y() - d / 2.0, d, d));
        }
    }
    else {
        useStroke(painter, color, stroke);
        painter.drawRoundedRect(rect, size * 0.18, size * 0.18);
        useFill(painter, color);
        painter.drawEllipse(QRectF(rect.center().x() - size * 0.06, rect.center().y() - size * 0.06, size * 0.12, size * 0.12));
    }

    painter.end();
    return image;
}

SfSymbolImageProvider::SfSymbolImageProvider()
    : QQuickImageProvider(QQuickImageProvider::Image)
{
}

QImage SfSymbolImageProvider::requestImage(const QString& id, QSize* size, const QSize& requestedSize)
{
    const QStringList parts = id.split(QLatin1Char('/'));
    const QString name = parts.value(0);
    int pointSize = parts.value(1).toInt();
    if (pointSize < 8) {
        pointSize = 8;
    }
    else if (pointSize > 96) {
        pointSize = 96;
    }

    QString hex = parts.value(2);
    if (!hex.startsWith(QLatin1Char('#'))) {
        hex.prepend(QLatin1Char('#'));
    }
    QColor color(hex);
    if (!color.isValid()) {
        color = QColor(Qt::white);
    }

    QImage image = twilightRenderSfSymbol(name, pointSize, color);
    if (image.isNull()) {
        const int pixelSize = requestedSize.width() > 0 ? requestedSize.width() : pointSize * 2;
        image = twilightDrawFallbackSymbol(name, pixelSize, color);
    }
    if (requestedSize.width() > 0 && requestedSize.height() > 0 && image.size() != requestedSize) {
        QImage fitted = image.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        QImage canvas(requestedSize, QImage::Format_ARGB32_Premultiplied);
        canvas.fill(Qt::transparent);
        QPainter painter(&canvas);
        painter.drawImage((requestedSize.width() - fitted.width()) / 2,
                          (requestedSize.height() - fitted.height()) / 2,
                          fitted);
        painter.end();
        image = canvas;
    }

    if (size != nullptr) {
        *size = image.size();
    }
    return image;
}
