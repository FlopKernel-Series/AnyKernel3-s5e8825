### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=FloppyKernel v6.2.2 for Exynos 1280 devices by @Flopster101
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=a25x
device.name2=a53x
device.name3=a33x
device.name4=m33x
device.name5=m34x
device.name6=gta4xls
device.name7=gta4xlswifi
device.name8=f34x
device.name9=a26xs
supported.versions=12.0-16.0
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install
## boot files attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# boot shell variables
BLOCK=/dev/block/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

ui_print "Detecting ROM type for patching..."

patch_for_aosp=1;
if [ ! -f /vendor/build.prop ]; then
  ui_print "Mounting /vendor"
  mount -o ro /vendor 2>/dev/null || mount -o ro /dev/block/mapper/vendor /vendor 2>/dev/null;
fi

if [ -d /vendor/overlay/ConnectivityOverlay ] || [ -d /vendor/overlay/TetheringOverlay ]; then
  ui_print "-> OneUI (Stock) ROM detected!"
  ui_print "No patch needed, using default cmdline."
  patch_for_aosp=0;
else
  ui_print "-> AOSP-based ROM detected!"
fi

# Apply the patch only if we've determined it's an AOSP ROM.
if [ "$patch_for_aosp" -eq 1 ]; then
  ui_print " "
  ui_print "Patching kernel for AOSP compatibility..."
  ui_print "aosp_mode=0 -> aosp_mode=1"

  # Use the magiskboot binary from the tools folder to perform the hex patch on the kernel Image file.
  # Original string: "aosp_mode=0" -> Hex: 616f73705f6d6f64653d30
  # New string:      "aosp_mode=1" -> Hex: 616f73705f6d6f64653d31
  $BIN/magiskboot hexpatch $AKHOME/Image \
    616f73705f6d6f64653d30 \
    616f73705f6d6f64653d31

  if [ $? -eq 0 ]; then
    ui_print "Kernel successfully patched."
  else
    ui_print "ERROR: Kernel hex patching failed! Aborting installation."
    exit 1
  fi
fi

ui_print " "
ui_print "Checking for unlocked mode feature flag..."

superfloppy_mode=-1;

# Check if /cache is mounted, try to mount if not
cache_mounted=0;
if mountpoint -q /cache 2>/dev/null; then
  cache_mounted=1;
else
  ui_print "Mounting /cache..."
  if mount /cache 2>/dev/null; then
    cache_mounted=1;
  else
    ui_print "Warning: Cannot mount /cache, unlocked flag will not be checked"
  fi
fi

# Check for feature flag file if /cache is accessible
if [ "$cache_mounted" -eq 1 ] && [ -f /cache/fk_feat ]; then
  # Extract superfloppy value from /cache/fk_feat (format: "superfloppy=1", "superfloppy=2", etc.)
  superfloppy_line=$(grep "^superfloppy=" /cache/fk_feat 2>/dev/null | head -1)
  if [ -n "$superfloppy_line" ]; then
    superfloppy_mode=$(echo "$superfloppy_line" | cut -d'=' -f2)
    # Validate mode is 1, 2, 3, 4 or 55
    if [ "$superfloppy_mode" != "1" ] && [ "$superfloppy_mode" != "2" ] && [ "$superfloppy_mode" != "3" ] && [ "$superfloppy_mode" != "4" ] && [ "$superfloppy_mode" != "5" ]; then
      superfloppy_mode=-1
    fi
  fi
fi

# Apply the patch only if superfloppy feature is enabled (mode 1, 2, 3, 4 or 5)
if [ "$superfloppy_mode" -ge 1 ] && [ "$superfloppy_mode" -le 5 ]; then
  ui_print "Unlocked mode: Enabled (Mode $superfloppy_mode)"
  ui_print " "
  ui_print "Patching kernel for unlocked mode..."

  # Hex values for superfloppy (hardcoded)
  # -1: superfloppy=-1 -> 7375706572666c6f7070793d2d31
  #  0: superfloppy=0  -> 7375706572666c6f7070793d30
  #  1: superfloppy=1  -> 7375706572666c6f7070793d31
  #  2: superfloppy=2  -> 7375706572666c6f7070793d32
  #  3: superfloppy=3  -> 7375706572666c6f7070793d33
  #  4: superfloppy=4  -> 7375706572666c6f7070793d34
  #  5: superfloppy=5  -> 7375706572666c6f7070793d35

  case "$superfloppy_mode" in
    1)
      new_hex="7375706572666c6f7070793d31"
      mode_name="Enabler"
      ;;
    2)
      new_hex="7375706572666c6f7070793d32"
      mode_name="MegaFloppy (2.6 GHz)"
      ;;
    3)
      new_hex="7375706572666c6f7070793d33"
      mode_name="UltraFloppy (2.7 GHz)"
      ;;
    4)
      new_hex="7375706572666c6f7070793d34"
      mode_name="CoolFloppy (2.112 GHz cap)"
      ;;
    5)
      new_hex="7375706572666c6f7070793d35"
      mode_name="BalancedFloppy (CL0 2.2 GHz)"
      ;;
  esac

  ui_print "Setting superfloppy mode to $superfloppy_mode ($mode_name)"

  # Try patching from all possible old values (-1, 0, 1, 2, 3, 4, 5) to the new value
  patch_success=0
  for old_val in -1 0 1 2 3 4 5; do
    case "$old_val" in
      -1) old_hex="7375706572666c6f7070793d2d31" ;;
      0)  old_hex="7375706572666c6f7070793d30" ;;
      1)  old_hex="7375706572666c6f7070793d31" ;;
      2)  old_hex="7375706572666c6f7070793d32" ;;
      3)  old_hex="7375706572666c6f7070793d33" ;;
      4)  old_hex="7375706572666c6f7070793d34" ;;
      5)  old_hex="7375706572666c6f7070793d35" ;;
    esac

    # Skip if old and new are the same (use string comparison to handle -1)
    if [ "$old_val" = "$superfloppy_mode" ]; then
      continue
    fi

    $BIN/magiskboot hexpatch $AKHOME/Image \
      "$old_hex" \
      "$new_hex" 2>/dev/null

    if [ $? -eq 0 ]; then
      ui_print "Patched from superfloppy=$old_val to superfloppy=$superfloppy_mode"
      patch_success=1
      break
    fi
  done

  if [ "$patch_success" -eq 0 ]; then
    # Check if already patched (kernel might already have the correct value)
    if hexdump -C $AKHOME/Image 2>/dev/null | grep -qi "$new_hex" 2>/dev/null; then
      ui_print "Kernel already has superfloppy=$superfloppy_mode set."
    else
      ui_print "ERROR: Kernel hex patching for unlocked mode failed! Aborting installation."
      exit 1
    fi
  else
    ui_print "Kernel successfully patched for unlocked mode."
  fi
else
  ui_print "Unlocked mode: Disabled"
fi

patch_for_perm=0;

# Check for feature flag file if /cache is accessible
if [ "$cache_mounted" -eq 1 ] && [ -f /cache/fk_feat ] && grep -q "force_perm" /cache/fk_feat 2>/dev/null; then
  patch_for_perm=1;
fi

# Apply the patch only if force_perm feature is enabled
if [ "$patch_for_perm" -eq 1 ]; then
  ui_print "Permissive mode: Enabled"
  ui_print " "
  ui_print "Patching kernel for permissive mode..."
  ui_print "force_perm=0 -> force_perm=1"

  # Use the magiskboot binary from the tools folder to perform the hex patch on the kernel Image file.
  # Original string: "force_perm=0" -> Hex: 666f7263655f7065726d3d30
  # New string:      "force_perm=1" -> Hex: 666f7263655f7065726d3d31
  $BIN/magiskboot hexpatch $AKHOME/Image \
    666f7263655f7065726d3d30 \
    666f7263655f7065726d3d31

  if [ $? -eq 0 ]; then
    ui_print "Kernel successfully patched for permissive mode."
  else
    ui_print "ERROR: Kernel hex patching for permissive mode failed! Aborting installation."
    exit 1
  fi
fi

patch_for_ems_efficient=0;

# Check for feature flag file if /cache is accessible
if [ "$cache_mounted" -eq 1 ] && [ -f /cache/fk_feat ] && grep -q "ems_efficient" /cache/fk_feat 2>/dev/null; then
  patch_for_ems_efficient=1;
fi

# Apply the patch only if ems_efficient feature is enabled
if [ "$patch_for_ems_efficient" -eq 1 ]; then
  ui_print "EMS efficient mode: Enabled"
  ui_print " "
  ui_print "Patching kernel for EMS efficient mode..."
  ui_print "ems_efficient=0 -> ems_efficient=1"

  # Use the magiskboot binary from the tools folder to perform the hex patch on the kernel Image file.
  # Original string: "ems_efficient=0" -> Hex: 656d735f656666696369656e743d30
  # New string:      "ems_efficient=1" -> Hex: 656d735f656666696369656e743d31
  $BIN/magiskboot hexpatch $AKHOME/Image \
    656d735f656666696369656e743d30 \
    656d735f656666696369656e743d31

  if [ $? -eq 0 ]; then
    ui_print "Kernel successfully patched for EMS efficient mode."
  else
    ui_print "ERROR: Kernel hex patching for EMS efficient mode failed! Aborting installation."
    exit 1
  fi
fi

# boot install
dump_boot; # use split_boot to skip ramdisk unpack, e.g. for devices with init_boot ramdisk

write_boot; # use flash_boot to skip ramdisk repack, e.g. for devices with init_boot ramdisk
## end boot install

flash_generic vendor_boot;

