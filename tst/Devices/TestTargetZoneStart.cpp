#include <gtest/gtest.h>

#include "devices/bike.h"

// T.Zone +/- holds its target like T.Power(W). The first press needs a start: the last requested power
// when it is a real target, otherwise the power ridden now. A start from 0 W made the tile hold
// 1% of FTP (2 W at FTP 200): resistance level 1 on a FitPlus bike, whose console then stopped the workout.

namespace {
const double kFtp = 200;

int start(bool tileHolds, bool programStarted, bool programRowHasPower, bool appSendsPower, double requested,
          double ridden) {
    return bike::targetZoneStartPower(tileHolds, programStarted, programRowHasPower, appSendsPower, requested,
                                      ridden, kFtp);
}
} // namespace

TEST(TargetZoneStart, FreeRideWithAppGradeStartsFromPowerRidden) {
    // Zwift in slope mode sends no power: the last requested power is 0
    EXPECT_EQ(start(false, false, false, false, 0, 29), 29);
    EXPECT_EQ(start(false, false, false, false, 0, 120.4), 120);
}

TEST(TargetZoneStart, OldRequestedPowerIsNotATarget) {
    // left from an earlier ERG ride or an earlier press that was released
    EXPECT_EQ(start(false, false, false, false, 2, 150), 150);
}

TEST(TargetZoneStart, CoastingHasNoStart) {
    // under 10% of FTP (20 W): the tile would hold almost no load
    EXPECT_EQ(start(false, false, false, false, 0, 0), 0);
    EXPECT_EQ(start(false, false, false, false, 0, 3), 0);
    EXPECT_EQ(start(false, false, false, false, 0, 19.4), 0);
    EXPECT_EQ(start(false, false, false, false, 0, 20), 20);
}

TEST(TargetZoneStart, TileHoldingATargetStepsFromIt) {
    EXPECT_EQ(start(true, false, false, false, 39, 31), 39);
    // even when the rider stops pedaling: "-" must still lower the held target
    EXPECT_EQ(start(true, false, false, false, 39, 0), 39);
}

TEST(TargetZoneStart, ProgramRowWithPowerStepsFromTheRow) {
    // the row power with the program offset, which is what the program sends every second
    EXPECT_EQ(start(false, true, true, false, 140, 128), 140);
    EXPECT_EQ(start(true, true, true, false, 140, 128), 140);
}

TEST(TargetZoneStart, ProgramRowWithoutPowerIgnoresTheOldTileTarget) {
    // pressed in an earlier power row: the tile loop does not run in a program, the old target is stale
    EXPECT_EQ(start(true, true, false, false, 170, 110), 110);
}

TEST(TargetZoneStart, AppErgTargetStepsFromTheAppTarget) {
    // the bike still ramps toward the app's 200 W
    EXPECT_EQ(start(false, false, false, true, 200, 150), 200);
    // not pedaling yet, the app's target is known
    EXPECT_EQ(start(false, false, false, true, 200, 0), 200);
}

TEST(TargetZoneStart, AppErgWithoutTargetStartsFromPowerRidden) {
    EXPECT_EQ(start(false, false, false, true, 0, 90), 90);
}

TEST(TargetZoneStart, SmallFtpStillNeedsSomePower) {
    EXPECT_EQ(bike::targetZoneStartPower(false, false, false, false, 0, 0, 5), 0);
    EXPECT_EQ(bike::targetZoneStartPower(false, false, false, false, 0, 1, 5), 1);
}
