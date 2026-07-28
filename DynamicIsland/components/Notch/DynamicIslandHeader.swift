/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Defaults
import SwiftUI

struct DynamicIslandHeader: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @Default(.settingsIconInNotch) private var settingsIconInNotch
    @Default(.showBatteryPercentInside) private var showBatteryPercentInside
    @Default(.showMinimalisticBatteryIndicator) private var showMinimalisticBatteryIndicator

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            if vm.notchState == .open {
                let spacerWidth = min(vm.closedNotchSize.width, 300)
                Rectangle()
                    .fill(.clear)
                    .frame(width: spacerWidth)
                    .mask { NotchShape() }
            }

            HStack(spacing: 4) {
                if vm.notchState == .open && settingsIconInNotch {
                    Button {
                        SettingsWindowController.shared.showWindow()
                    } label: {
                        Capsule()
                            .fill(.black)
                            .frame(width: 30, height: 30)
                            .overlay {
                                Image(systemName: "gear")
                                    .foregroundColor(.white)
                                    .imageScale(.medium)
                            }
                    }
                    .buttonStyle(.plain)
                }

                if vm.notchState == .open,
                   !shouldUseDynamicIslandMode(for: vm.screen),
                   showMinimalisticBatteryIndicator {
                    MinimalisticBatteryView(
                        levelBattery: batteryModel.levelBattery,
                        isPluggedIn: batteryModel.isPluggedIn,
                        isCharging: batteryModel.isCharging,
                        isInLowPowerMode: batteryModel.isInLowPowerMode,
                        bodyWidth: 28,
                        bodyHeight: 14,
                        isForNotification: false,
                        showPercentInside: showBatteryPercentInside
                    )
                    .padding(.trailing, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(8)
        }
    }
}
