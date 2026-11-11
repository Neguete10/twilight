#pragma once

#include <QString>
#include <QXmlStreamReader>

// Tag text and the current-game rule from a GameStream serverinfo or applist
// document. NvHTTP::getXmlString and NvHTTP::getCurrentGame call these.

inline QString nvXmlTagText(const QString& xml, const QString& tagName)
{
    QXmlStreamReader xmlReader(xml);

    while (!xmlReader.atEnd()) {
        if (xmlReader.readNext() != QXmlStreamReader::StartElement) {
            continue;
        }

        if (xmlReader.name() == tagName) {
            return xmlReader.readElementText();
        }
    }

    return QString();
}

inline int nvCurrentGameId(const QString& serverInfo)
{
    // GFE 2.8 started keeping currentgame set to the last game played. As a result, it no longer
    // has the semantics that its name would indicate. To contain the effects of this change as much
    // as possible, we'll force the current game to zero if the server isn't in a streaming session.
    const QString serverState = nvXmlTagText(serverInfo, QStringLiteral("state"));
    if (serverState.endsWith(QLatin1String("_SERVER_BUSY"))) {
        return nvXmlTagText(serverInfo, QStringLiteral("currentgame")).toInt();
    }
    return 0;
}

inline bool nvPairStatusIsPaired(const QString& serverInfo)
{
    return nvXmlTagText(serverInfo, QStringLiteral("PairStatus")) == QLatin1String("1");
}
