#include "nvaddress.h"

#include <QUrl>

#include <QHostAddress>

NvAddress::NvAddress()
{
    setAddress(nullptr);
    setPort(0);
}

NvAddress::NvAddress(QString addr, uint16_t port)
{
    setAddress(addr);
    setPort(port);
}

NvAddress::NvAddress(QHostAddress addr, uint16_t port)
{
    setAddress(addr);
    setPort(port);
}

uint16_t NvAddress::port() const
{
    return m_Port;
}

QString NvAddress::address() const
{
    return m_Address;
}

void NvAddress::setPort(uint16_t port)
{
    m_Port = port;
}

void NvAddress::setAddress(QString addr)
{
    m_Address = addr;
}

void NvAddress::setAddress(QHostAddress addr)
{
    m_Address = addr.toString();
}

bool NvAddress::isNull() const
{
    return m_Address.isEmpty();
}

bool NvAddress::parseManualHost(const QString& address, QString* hostOut, uint16_t* portOut)
{
    const QUrl url = QUrl::fromUserInput(QStringLiteral("moonlight://") + address);
    if (url.isValid() && !url.host().isEmpty() && url.scheme() == QLatin1String("moonlight")) {
        if (hostOut) {
            *hostOut = url.host();
        }
        if (portOut) {
            *portOut = static_cast<uint16_t>(url.port(DEFAULT_HTTP_PORT));
        }
        return true;
    }

    if (QHostAddress(address).protocol() == QAbstractSocket::IPv6Protocol) {
        if (hostOut) {
            *hostOut = address;
        }
        if (portOut) {
            *portOut = DEFAULT_HTTP_PORT;
        }
        return true;
    }

    return false;
}

QString NvAddress::toString() const
{
    if (m_Address.isEmpty()) {
        return "<NULL>";
    }

    if (QHostAddress(m_Address).protocol() == QAbstractSocket::IPv6Protocol) {
        return QString("[%1]:%2").arg(m_Address).arg(m_Port);
    }
    else {
        return QString("%1:%2").arg(m_Address).arg(m_Port);
    }
}
