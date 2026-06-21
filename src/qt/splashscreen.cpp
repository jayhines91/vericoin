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
#include <QKeyEvent>
#include <QPainter>
#include <QPainterPath>
#include <QRadialGradient>
#include <QScreen>


static void PaintReleaseSplash(
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

    QPixmap logoPixmap(":/icons/vrcsplashlogo");
    if (!GUIUtil::IsVericoin())
        logoPixmap = QPixmap(":/icons/vrmsplashlogo");

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

SplashScreen::SplashScreen(interfaces::Node& node, Qt::WindowFlags f, const NetworkStyle *networkStyle) :
    QWidget(nullptr, f), curAlignment(0), m_node(node)
{
    QString titleText = GUIUtil::GetCoinName();
    QString versionText = QString("%1.%2.%3")
                              .arg(QString::number(CLIENT_VERSION_MAJOR))
                              .arg(QString::number(CLIENT_VERSION_MINOR))
                              .arg(QString::number(CLIENT_VERSION_REVISION));
#if ENABLE_DEV_HELPER_WINDOW
    if (IsDeveloperEditionActive())
        versionText += QStringLiteral(" Dev Edition");
#endif
#if ENABLE_BETA_BUILD
    versionText += QStringLiteral(" Beta");
#endif
    const QString titleAddText = networkStyle->getTitleAddText();
    const QString font = QApplication::font().toString();

    setAttribute(Qt::WA_TranslucentBackground);
    setWindowFlags(Qt::FramelessWindowHint);

    const QSize splashSize(380, 200);
    PaintReleaseSplash(pixmap, splashSize, versionText, titleAddText, font);

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
        Q_ARG(int, Qt::AlignBottom|Qt::AlignHCenter),
        Q_ARG(QColor, QColor(55,55,55)));
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
    painter.drawPixmap(0, 0, pixmap);
    QRect r = rect().adjusted(5, 5, -5, -5);
    painter.setPen(curColor);
    painter.drawText(r, curAlignment, curMessage);
}

void SplashScreen::closeEvent(QCloseEvent *event)
{
    m_node.startShutdown();
    event->ignore();
}
