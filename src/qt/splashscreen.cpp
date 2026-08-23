// Copyright (c) 2011-2018 The Bitcoin Core developers
// Copyright (c) 2026 The Vericoin developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#if defined(HAVE_CONFIG_H)
#include <config/bitcoin-config.h>
#endif

#include <qt/splashscreen.h>

#include <clientversion.h>
#include <interfaces/handler.h>
#include <interfaces/node.h>
#include <interfaces/wallet.h>
#include <qt/guiutil.h>
#include <qt/networkstyle.h>
#include <ui_interface.h>
#include <util/devhelperconfig.h>
#include <util/devedition.h>

#include <QApplication>
#include <QCloseEvent>
#include <QFont>
#include <QKeyEvent>
#include <QPainter>
#include <QPainterPath>
#include <QRadialGradient>
#include <QScreen>

#include <cmath>

namespace {

/** Splash overlay text — tuned for white PNG background (not main-window chrome). */
constexpr QColor kSplashVersionColor(0x3b, 0x8f, 0xd9);
constexpr QColor kSplashStatusColor(0x5a, 0x70, 0x88);

static QString BuildSplashVersionLine1()
{
    QString version = QStringLiteral("v%1.%2.%3")
                          .arg(QString::number(CLIENT_VERSION_MAJOR))
                          .arg(QString::number(CLIENT_VERSION_MINOR))
                          .arg(QString::number(CLIENT_VERSION_REVISION));
#if CLIENT_VERSION_BUILD != 0
    version += QStringLiteral(".%1").arg(QString::number(CLIENT_VERSION_BUILD));
#endif
    return version;
}

static QString BuildSplashVersionLine2()
{
#if ENABLE_DEV_HELPER_WINDOW
    if (IsDeveloperEditionActive()) {
        return QStringLiteral("Dev Edition");
    }
#endif
#if ENABLE_BETA_BUILD
    return QStringLiteral("Beta");
#endif
    return QString();
}

static void PaintLegacyReleaseSplash(
    QPixmap& pixmap,
    const QSize& splashSize,
    const QString& versionText,
    const QString& titleAddText,
    const QString& fontFamily)
{
    pixmap = QPixmap(splashSize);
    pixmap.fill(Qt::transparent);

    QPainter pixPaint(&pixmap);
    pixPaint.setRenderHint(QPainter::Antialiasing);

    QPainterPath mainPath;
    const QRect mainRect(QPoint(0, 0), splashSize);
    mainPath.addRoundedRect(mainRect, 20, 20);

    QRadialGradient gradient(QPoint(0, 0), splashSize.width());
    gradient.setColorAt(0, Qt::white);
    gradient.setColorAt(1, QColor(247, 247, 247));
    pixPaint.fillPath(mainPath, gradient);
    pixPaint.drawPath(mainPath);

    const QRect rLogo(QPoint((splashSize.width() - 350) / 2, 10), QSize(350, 112));

    QPixmap logoPixmap(":/icons/vrmsplashlogo");
    const QPixmap logo = logoPixmap.scaledToHeight(112, Qt::SmoothTransformation);
    pixPaint.drawPixmap(rLogo, logo);

    pixPaint.setFont(QFont(fontFamily, 15));

    const QRect rText(0, 142, splashSize.width(), 30);
    pixPaint.fillRect(rText, QColor(132, 180, 221));
    pixPaint.setPen(Qt::white);
    pixPaint.drawText(rText, Qt::AlignCenter,
        versionText + (titleAddText.isEmpty() ? QString() : QStringLiteral(" · ") + titleAddText));

    pixPaint.end();
}

static qreal SplashDevicePixelRatio()
{
    if (QScreen* screen = QGuiApplication::primaryScreen()) {
        return screen->devicePixelRatio();
    }
    return 1.0;
}

static QSize SplashLogicalSize(const QPixmap& source)
{
    constexpr int kSplashWidth = 600;
    if (source.isNull() || source.width() <= 0) {
        return QSize(kSplashWidth, 210);
    }
    const int height = std::max(1, (source.height() * kSplashWidth) / source.width());
    return QSize(kSplashWidth, height);
}

static void PaintModernVericoinSplash(
    QPixmap& pixmap,
    const QString& versionLine1,
    const QString& versionLine2,
    const QString& fontFamily)
{
    const QPixmap source(QStringLiteral(":/icons/vrcsplashbg"));
    const QSize logicalSize = SplashLogicalSize(source.isNull() ? QPixmap(":/icons/vrcsplashlogo") : source);
    const qreal dpr = SplashDevicePixelRatio();
    const QSize pixelSize(
        std::max(1, static_cast<int>(std::lround(logicalSize.width() * dpr))),
        std::max(1, static_cast<int>(std::lround(logicalSize.height() * dpr))));

    pixmap = QPixmap(pixelSize);
    pixmap.fill(Qt::transparent);
    pixmap.setDevicePixelRatio(dpr);

    QPainter pixPaint(&pixmap);
    pixPaint.setRenderHint(QPainter::SmoothPixmapTransform);

    QPixmap background = source;
    if (background.isNull()) {
        background = QPixmap(QStringLiteral(":/icons/vrcsplashlogo"));
    }
    if (!background.isNull()) {
        const int radius = std::max(8, logicalSize.width() * 13 / 600);
        QPainterPath clipPath;
        clipPath.addRoundedRect(QRectF(QPoint(0, 0), logicalSize), radius, radius);
        pixPaint.setClipPath(clipPath);
        pixPaint.drawPixmap(QRect(QPoint(0, 0), logicalSize), background);
        pixPaint.setClipping(false);
    }

    pixPaint.setRenderHint(QPainter::Antialiasing);

    // Version/status sit in the PNG's lower margin — do not paint a bar over the artwork.
    const int rightPad = std::max(14, logicalSize.width() * 14 / 600);
    const int bottomPad = std::max(10, logicalSize.height() * 12 / 210);
    const int lineGap = 2;
    const int versionZoneWidth = std::max(160, logicalSize.width() * 150 / 600);

    QFont versionFont(fontFamily, 11, QFont::DemiBold);
    versionFont.setPointSizeF(11.0 * logicalSize.width() / 600.0);
    pixPaint.setFont(versionFont);
    pixPaint.setPen(kSplashVersionColor);

    QFontMetrics versionMetrics(versionFont);
    const int line1Height = versionMetrics.height();
    int textBottom = logicalSize.height() - bottomPad;

    if (!versionLine2.isEmpty()) {
        QFont suffixFont(fontFamily, 9);
        suffixFont.setPointSizeF(9.0 * logicalSize.width() / 600.0);
        pixPaint.setFont(suffixFont);
        pixPaint.setPen(kSplashStatusColor);
        QFontMetrics suffixMetrics(suffixFont);
        const QRect suffixRect(
            logicalSize.width() - versionZoneWidth - rightPad,
            textBottom - suffixMetrics.height(),
            versionZoneWidth,
            suffixMetrics.height());
        pixPaint.drawText(suffixRect, Qt::AlignRight | Qt::AlignVCenter, versionLine2);
        textBottom = suffixRect.top() - lineGap;
    }

    pixPaint.setFont(versionFont);
    pixPaint.setPen(kSplashVersionColor);
    const QRect versionRect(
        logicalSize.width() - versionZoneWidth - rightPad,
        textBottom - line1Height,
        versionZoneWidth,
        line1Height);
    pixPaint.drawText(versionRect, Qt::AlignRight | Qt::AlignVCenter, versionLine1);

    pixPaint.end();
}

} // namespace

SplashScreen::SplashScreen(interfaces::Node& node, Qt::WindowFlags f, const NetworkStyle *networkStyle) :
    QWidget(nullptr, f), curAlignment(0), m_node(node)
{
    QString titleText = GUIUtil::GetCoinName();
    const QString versionLine1 = BuildSplashVersionLine1();
    const QString versionLine2 = BuildSplashVersionLine2();
    const QString titleAddText = networkStyle->getTitleAddText();
    const QString font = QApplication::font().family();

    setAttribute(Qt::WA_TranslucentBackground);
    setWindowFlags(Qt::FramelessWindowHint);

    QSize splashSize(600, 210);
    if (GUIUtil::IsVericoin()) {
        PaintModernVericoinSplash(pixmap, versionLine1, versionLine2, font);
        if (!pixmap.isNull()) {
            splashSize = QSize(
                std::max(1, static_cast<int>(std::lround(pixmap.width() / pixmap.devicePixelRatio()))),
                std::max(1, static_cast<int>(std::lround(pixmap.height() / pixmap.devicePixelRatio()))));
        }
    } else {
        QString versionText = versionLine1;
        versionText.remove(0, 1); // drop leading "v" for legacy Verium bar
        if (!versionLine2.isEmpty()) {
            versionText += QStringLiteral(" ") + versionLine2;
        }
        splashSize = QSize(380, 200);
        PaintLegacyReleaseSplash(pixmap, splashSize, versionText, titleAddText, font);
    }

#if ENABLE_DEV_HELPER_WINDOW
    if (IsDeveloperEditionActive())
        setWindowTitle(QString::fromStdString(GetDeveloperEditionTitle())
                       + (titleAddText.isEmpty() ? QString() : QStringLiteral(" · ") + titleAddText));
    else
#endif
#if ENABLE_BETA_BUILD
        setWindowTitle(titleText + QStringLiteral(" Beta")
                       + (titleAddText.isEmpty() ? QString() : QStringLiteral(" · ") + titleAddText));
#else
        setWindowTitle(titleText + QStringLiteral(" ") + titleAddText);
#endif

    const QRect r(QPoint(), splashSize);
    resize(r.size());
    setFixedSize(r.size());
    move(QGuiApplication::primaryScreen()->geometry().center() - r.center());

    subscribeToCoreSignals();
    installEventFilter(this);
}

SplashScreen::~SplashScreen()
{
    unsubscribeFromCoreSignals();
}

bool SplashScreen::eventFilter(QObject * obj, QEvent * ev) {
    if (ev->type() == QEvent::KeyPress) {
        QKeyEvent *keyEvent = static_cast<QKeyEvent *>(ev);
        if (keyEvent->key() == Qt::Key_Q) {
            m_node.startShutdown();
        }
    }
    return QObject::eventFilter(obj, ev);
}

void SplashScreen::finish()
{
    if (isMinimized())
        showNormal();
    hide();
    deleteLater();
}

static void InitMessage(SplashScreen *splash, const std::string &message)
{
    bool invoked = QMetaObject::invokeMethod(splash, "showMessage",
        Qt::QueuedConnection,
        Q_ARG(QString, QString::fromStdString(message)),
        Q_ARG(int, Qt::AlignBottom | Qt::AlignLeft),
        Q_ARG(QColor, kSplashStatusColor));
    assert(invoked);
}

static void ShowProgress(SplashScreen *splash, const std::string &title, int nProgress, bool resume_possible)
{
    InitMessage(splash, title + strprintf("(%d)", nProgress) + "%");
}
#ifdef ENABLE_WALLET
void SplashScreen::ConnectWallet(std::unique_ptr<interfaces::Wallet> wallet)
{
    m_connected_wallet_handlers.emplace_back(wallet->handleShowProgress(std::bind(ShowProgress, this, std::placeholders::_1, std::placeholders::_2, false)));
    m_connected_wallets.emplace_back(std::move(wallet));
}
#endif

void SplashScreen::subscribeToCoreSignals()
{
    m_handler_init_message = m_node.handleInitMessage(std::bind(InitMessage, this, std::placeholders::_1));
    m_handler_show_progress = m_node.handleShowProgress(std::bind(ShowProgress, this, std::placeholders::_1, std::placeholders::_2, std::placeholders::_3));
#ifdef ENABLE_WALLET
    m_handler_load_wallet = m_node.handleLoadWallet([this](std::unique_ptr<interfaces::Wallet> wallet) { ConnectWallet(std::move(wallet)); });
#endif
}

void SplashScreen::unsubscribeFromCoreSignals()
{
    m_handler_init_message->disconnect();
    m_handler_show_progress->disconnect();
    for (const auto& handler : m_connected_wallet_handlers) {
        handler->disconnect();
    }
    m_connected_wallet_handlers.clear();
    m_connected_wallets.clear();
}

void SplashScreen::showMessage(const QString &message, int alignment, const QColor &color)
{
    curMessage = message;
    curAlignment = alignment;
    curColor = color;
    update();
}

void SplashScreen::paintEvent(QPaintEvent *event)
{
    QPainter painter(this);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.drawPixmap(0, 0, pixmap);

    if (curMessage.isEmpty()) {
        return;
    }

    painter.setPen(curColor);
    QFont statusFont = painter.font();
    statusFont.setPointSizeF(GUIUtil::IsVericoin() ? 10.0 * width() / 600.0 : 10.0);
    painter.setFont(statusFont);

    const int versionReserve = GUIUtil::IsVericoin() ? std::max(150, width() * 150 / 600) : 20;
    const int sidePad = GUIUtil::IsVericoin() ? std::max(14, width() * 14 / 600) : 14;
    const QRect statusRect = rect().adjusted(sidePad, 8, -(sidePad + versionReserve), -10);
    painter.drawText(statusRect, curAlignment | Qt::TextWordWrap, curMessage);
}

void SplashScreen::closeEvent(QCloseEvent *event)
{
    m_node.startShutdown();
    event->ignore();
}
