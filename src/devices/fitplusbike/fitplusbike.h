#ifndef FITPLUSBIKE_H
#define FITPLUSBIKE_H

#include <QBluetoothDeviceDiscoveryAgent>
#include <QtBluetooth/qlowenergyadvertisingdata.h>
#include <QtBluetooth/qlowenergyadvertisingparameters.h>
#include <QtBluetooth/qlowenergycharacteristic.h>
#include <QtBluetooth/qlowenergycharacteristicdata.h>
#include <QtBluetooth/qlowenergycontroller.h>
#include <QtBluetooth/qlowenergydescriptordata.h>
#include <QtBluetooth/qlowenergyservice.h>
#include <QtBluetooth/qlowenergyservicedata.h>
#include <QtCore/qbytearray.h>

#ifndef Q_OS_ANDROID
#include <QtCore/qcoreapplication.h>
#else
#include <QtGui/qguiapplication.h>
#endif
#include <QtCore/qlist.h>
#include <QtCore/qmutex.h>
#include <QtCore/qscopedpointer.h>
#include <QtCore/qtimer.h>

#include <QDateTime>
#include <QObject>
#include <QString>

#include "devices/bike.h"
#include "virtualdevices/virtualbike.h"

#ifdef Q_OS_IOS
#include "ios/lockscreen.h"
#endif

class fitplusbike : public bike {
    Q_OBJECT
  public:
    fitplusbike(bool noWriteResistance, bool noHeartService, int8_t bikeResistanceOffset, double bikeResistanceGain);
    resistance_t maxResistance() override { return max_resistance; }
    resistance_t pelotonToBikeResistance(int pelotonResistance) override;
    bool connected() override;
    resistance_t resistanceFromPowerRequest(uint16_t power) override;

  private:
    resistance_t max_resistance = 24;
    void btinit();
    void noteWorkoutStatus(int status, qint64 nowMs);
    void writeCharacteristic(uint8_t *data, uint8_t data_len, const QString &info, bool disable_log = false,
                             bool wait_for_response = false);
    void startDiscover();
    void forceResistance(resistance_t requestResistance);
    void sendPoll();
    double bikeResistanceToPeloton(double resistance);
    uint16_t watts() override;
    uint16_t wattsFromResistance(double resistance);

    QTimer *refresh;

    QLowEnergyService *gattCommunicationChannelService = nullptr;
    QLowEnergyService *gattCommunicationChannelServiceFTMS = nullptr;
    QLowEnergyCharacteristic gattWriteCharacteristic;
    QLowEnergyCharacteristic gattNotify1Characteristic;
    QLowEnergyCharacteristic gattNotifyFTMSCharacteristic;

    int8_t bikeResistanceOffset = 4;
    double bikeResistanceGain = 1.0;
    uint8_t counterPoll = 1;
    uint8_t sec1Update = 0;
    QByteArray lastPacket;
    QDateTime lastRefreshCharacteristicChanged = QDateTime::currentDateTime();
    uint8_t firstStateChanged = 0;
    resistance_t lastResistanceBeforeDisconnection = -1;
    bool requestResistanceCompleted = true;

    bool initDone = false;
    bool initRequest = false;

    bool noWriteResistance = false;
    bool noHeartService = false;

    bool merach_MRK = false;
    bool H9110_OSAKA = false;
    bool virtufitEtappe = false;
    bool virtufitLayoutDetected = false;
    bool validFrameSeen = false;

    // Virtufit Etappe workout state from the 02 42 <status> frames: 00 stopped, 01 starting, 02 running.
    // The bike sets its own default level when a workout starts and ignores level commands while stopped.
    int workoutStatus = -1;
    qint64 workoutRunningSinceMs = 0;
    uint8_t workoutRestarts = 0;
    bool workoutRestartRequest = false;
    // the start repeat while the bike has not run since the init (any mode with FitShow status frames)
    bool workoutEverRunning = false;
    bool unstartedWorkoutWarned = false;
    qint64 workoutStoppedSinceMs = 0;
    qint64 initDoneMs = 0;
    qint64 lastStartSentMs = 0;
    // stop or pause pressed in QZ: the bike may stop then, a stop from its console is undone
    bool appStopped = false;
    resistance_t lastForcedResistance = -1;

#ifdef Q_OS_IOS
    lockscreen *h = 0;
#endif

  Q_SIGNALS:
    void disconnected();

  public slots:
    void deviceDiscovered(const QBluetoothDeviceInfo &device);

  private slots:

    void characteristicChanged(const QLowEnergyCharacteristic &characteristic, const QByteArray &newValue);
    void characteristicWritten(const QLowEnergyCharacteristic &characteristic, const QByteArray &newValue);
    void descriptorWritten(const QLowEnergyDescriptor &descriptor, const QByteArray &newValue);
    void stateChanged(QLowEnergyService::ServiceState state);
    void controllerStateChanged(QLowEnergyController::ControllerState state);

    void serviceDiscovered(const QBluetoothUuid &gatt);
    void serviceScanDone(void);
    void update();
    void virtufitLayoutAnswered(bool enable);
    void error(QLowEnergyController::Error err);
    void errorService(QLowEnergyService::ServiceError);
};

#endif // FITPLUSBIKE_H
