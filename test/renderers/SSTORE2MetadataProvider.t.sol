// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/globals/Globals.sol";
import "../../contracts/renderers/MetadataProvider.sol";
import "../../contracts/renderers/SSTORE2MetadataProvider.sol";

import "../TestUtils.sol";

contract SSTORE2MetadataProviderTest is Test, TestUtils {
    Globals globals = new Globals(address(this));
    MetadataProvider metadataProvider = new MetadataProvider(globals);
    SSTORE2MetadataProvider metadataProviderSSTORE2 = new SSTORE2MetadataProvider(globals);

    bytes data =
        hex"0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000003c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e64732e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000035697066733a2f2f516d553573594778587679656b5265777a344238427662356538786174426e4d564c5a507246386d706934617350000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e64732e0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000003c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e64732e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000035697066733a2f2f516d553573594778587679656b5265777a344238427662356538786174426e4d564c5a507246386d706934617350000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e6473230000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000003c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e64732e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000035697066733a2f2f516d553573594778587679656b5265777a344238427662356538786174426e4d564c5a507246386d706934617350000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e64732e0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000003c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e64732e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000035697066733a2f2f516d553573594778587679656b5265777a344238427662356538786174426e4d564c5a507246386d706934617350000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e64732e0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000003c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e64732e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000035697066733a2f2f516d553573594778587679656b5265777a344238427662356538786174426e4d564c5a507246386d706934617350000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e64732e0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000003c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e64732e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000035697066733a2f2f516d553573594778587679656b5265777a344238427662356538786174426e4d564c5a507246386d706934617350000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e6473230000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000003c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e64732e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000035697066733a2f2f516d553573594778587679656b5265777a344238427662356538786174426e4d564c5a507246386d706934617350000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e64732e0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000003c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e64732e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000035697066733a2f2f516d553573594778587679656b5265777a344238427662356538786174426e4d564c5a507246386d706934617350000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e64732e0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000003c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e64732e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000035697066733a2f2f516d553573594778587679656b5265777a344238427662356538786174426e4d564c5a507246386d706934617350000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e64732e0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000003c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e64732e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000035697066733a2f2f516d553573594778587679656b5265777a344238427662356538786174426e4d564c5a507246386d706934617350000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e6473230000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000003c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e64732e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000035697066733a2f2f516d553573594778587679656b5265777a344238427662356538786174426e4d564c5a507246386d706934617350000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e64732e0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000003c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e64732e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000035697066733a2f2f516d553573594778587679656b5265777a344238427662356538786174426e4d564c5a507246386d706934617350000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c666c697070656420616e642077617270656420746f61642063726577000000000000000000000000000000000000000000000000000000000000000000000053576527726520737570706f7274696e672074686520666c697070656420616e642077617270656420746f61642065636f73797374656d2e20204c6574277320676f206765742027656d2c20667269656e64732e0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000002e0000000000000000000000000000000000000000000000000";

    function test_setMetadata_withSSTORE() public {
        metadataProvider.setMetadata(address(this), abi.encodePacked(data, data));
    }

    function test_setMetadata_withSSTORE2() public {
        bytes[] memory metadataPartitions = new bytes[](2);
        metadataPartitions[0] = data;
        metadataPartitions[1] = data;

        metadataProviderSSTORE2.setMetadata(address(this), metadataPartitions);
    }
}
