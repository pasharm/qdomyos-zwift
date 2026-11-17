#include <gtest/gtest.h>

#include "devices/bike.h"

// T.Zone +/- holds its target like T.Power(W). The first press needs a start: the last requested power
// when it is a real target (the tile's own, a program row's, or the one QZ keeps on the bike for an app in
// ERG), otherwise the power ridden now. A start from 0 W made the tile hold
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

TEST(TargetZoneStart, HeldTargetOfZeroIsNoTarget) {
    // the tile loop needs a target above 0, so there is nothing held
    EXPECT_EQ(start(true, false, false, false, 0, 120), 120);
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
    // appSendsPower: the app is in ERG and QZ keeps the last requested power on the bike (homeform). The bike
    // still ramps toward 200 W
    EXPECT_EQ(start(false, false, false, true, 200, 150), 200);
    // not pedaling yet, the app's target just came
    EXPECT_EQ(start(false, false, false, true, 200, 0), 200);
    // after Pause/Start the bike still gets the tile's 230 W until the app's next target
    EXPECT_EQ(start(false, false, false, true, 230, 195), 230);
}

TEST(TargetZoneStart, AppErgWithoutTargetStartsFromPowerRidden) {
    EXPECT_EQ(start(false, false, false, true, 0, 90), 90);
}

TEST(TargetZoneStart, TileHoldsWithoutOwnErgOverTheApp) {
    // the T.Power(W) loop re-sends the tile's target over the app's commands
    EXPECT_TRUE(bike::targetZoneTileHoldsTarget(true, false, false));
    EXPECT_TRUE(bike::targetZoneTileHoldsTarget(true, false, true));
    EXPECT_FALSE(bike::targetZoneTileHoldsTarget(false, false, false));
}

TEST(TargetZoneStart, OwnErgBikeKeepsTheTargetWhileTheAppIsSilent) {
    // free ride without an app: quick presses add up, as on T.Power(W)
    EXPECT_TRUE(bike::targetZoneTileHoldsTarget(true, true, false));
    // the app's frame in the last 2 s: the bike may follow the app's grade, the old target is not held
    EXPECT_FALSE(bike::targetZoneTileHoldsTarget(true, true, true));
    EXPECT_FALSE(bike::targetZoneTileHoldsTarget(false, true, false));
}

TEST(TargetZoneStart, OwnErgBikeQuickPressesStepFromTheTarget) {
    // target 200 W, the bike still ramps up, 170 W ridden: "-" lowers the target, not the power ridden
    const bool holds = bike::targetZoneTileHoldsTarget(true, true, false);
    EXPECT_EQ(start(holds, false, false, false, 200, 170), 200);
}

TEST(TargetZoneStart, SmallFtpStillNeedsSomePower) {
    EXPECT_EQ(bike::targetZoneStartPower(false, false, false, false, 0, 0, 5), 0);
    EXPECT_EQ(bike::targetZoneStartPower(false, false, false, false, 0, 1, 5), 1);
}
