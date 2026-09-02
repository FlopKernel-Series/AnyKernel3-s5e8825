### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=FloppyKernel v6.3.3 for Exynos 1280 devices by @Flopster101
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

printed_blank=0
print_blank_once() {
  if [ "$printed_blank" -eq 0 ]; then
    ui_print " "
    printed_blank=1
  fi
}
log_rom()  { print_blank_once; ui_print "[ROM] $1"; }
log_feat() { print_blank_once; ui_print "[FK]  $1"; }
log_warn() { print_blank_once; ui_print "[!]   $1"; }

apply_aosp_mode() {
  local mode=$1
  local hex_0="616f73705f6d6f64653d30"
  local hex_1="616f73705f6d6f64653d31"

  [ "$mode" = "1" ] || return 0
  [ -f "$AKHOME/Image" ] || return 0

  $BIN/magiskboot hexpatch "$AKHOME/Image" "$hex_0" "$hex_1" >/dev/null 2>&1
}

apply_usb_aoffload_disable() {
  local mode=$1
  local hex_0="7573625f616f66666c6f61645f64697361626c653d30"
  local hex_1="7573625f616f66666c6f61645f64697361626c653d31"

  [ "$mode" = "1" ] || return 0
  [ -f "$AKHOME/Image" ] || return 0

  $BIN/magiskboot hexpatch "$AKHOME/Image" "$hex_0" "$hex_1" >/dev/null 2>&1
}

check_usb_aoffload_support() {
  if [ "$cache_mounted" -eq 1 ] && [ -f /cache/fk_feat ] && \
     grep -q "usb_aoffload_disable=" /cache/fk_feat 2>/dev/null; then
    val=$(grep -o 'usb_aoffload_disable=[0-9]*' /cache/fk_feat | head -n1 | cut -d= -f2)
    log_rom "USB Audio Offload: override (usb_aoffload_disable=$val)"
    apply_usb_aoffload_disable "$val"
    return 0
  fi

  local lib_audioproxy=""
  if [ -f /vendor/lib64/libaudioproxy.so ]; then
    lib_audioproxy="/vendor/lib64/libaudioproxy.so"
  elif [ -f /vendor/lib/libaudioproxy.so ]; then
    lib_audioproxy="/vendor/lib/libaudioproxy.so"
  fi

  if [ -n "$lib_audioproxy" ] && strings "$lib_audioproxy" 2>/dev/null | grep -q "audio_hw_proxy_usb"; then
    log_rom "USB Audio Offload: HAL support detected"
  else
    log_rom "USB Audio Offload: unsupported by HAL"
    apply_usb_aoffload_disable 1
    if [ $? -eq 0 ]; then
      log_feat "usb_aoffload_disable: patched (0 -> 1)"
    else
      log_warn "usb_aoffload_disable: hex patch failed!"
    fi
  fi
}

detect_aosp_mode() {
  if [ "$cache_mounted" -eq 1 ] && [ -f /cache/fk_feat ] && \
     grep -q "aosp_mode=" /cache/fk_feat 2>/dev/null; then
    val=$(grep -o 'aosp_mode=[0-9]*' /cache/fk_feat | head -n1 | cut -d= -f2)
    log_rom "Vendor type: override (aosp_mode=$val)"
    apply_aosp_mode "$val"
    if [ "$val" -eq 1 ]; then
      check_usb_aoffload_support
    fi
    return 0
  fi

  if ! grep -q ' /vendor ' /proc/mounts 2>/dev/null; then
    mount -o ro /vendor 2>/dev/null || mount -o ro /dev/block/mapper/vendor /vendor 2>/dev/null
  fi

  vendor_src=$(grep ' /vendor ' /proc/mounts 2>/dev/null | tail -n1 | awk '{print $1}')
  case "$vendor_src" in
    /dev/block/*) ;;
    *)
      log_rom "Vendor type: OneUI or stock-based (vendor not block-mounted)"
      return 0
      ;;
  esac

  if [ -d /vendor/overlay/ConnectivityOverlay ] || [ -d /vendor/overlay/TetheringOverlay ]; then
    log_rom "Vendor type: OneUI or stock-based"
  else
    log_rom "Vendor type: AOSP"
    apply_aosp_mode 1
    if [ $? -eq 0 ]; then
      log_feat "aosp_mode: patched (0 -> 1)"
      check_usb_aoffload_support
    else
      log_warn "aosp_mode: hex patch failed! Aborting installation."
      exit 1
    fi
  fi
}

repack_vendor_boot_modules() {
  local block dlkm_fragment dtb_file path workdir

  dlkm_fragment="$AKHOME/vendor_ramdisk_dlkm.lz4"
  dtb_file="$AKHOME/platform.dtb"
  [ -f "$dlkm_fragment" ] || abort "Vendor DLKM ramdisk is missing. Aborting..."
  [ -f "$dtb_file" ] || abort "Vendor platform DTB is missing. Aborting..."

  for path in /dev/block/by-name /dev/block/bootdevice/by-name; do
    for block in "$path/vendor_boot$SLOT" "$path/vendor_boot"; do
      [ -e "$block" ] && break 2
    done
  done
  [ -e "$block" ] || abort "vendor_boot partition could not be found. Aborting..."

  workdir="$AKHOME/vendor_boot-work"
  mkdir -p "$workdir" || abort "Failed to prepare vendor_boot workspace. Aborting..."

  ui_print " " "Backing up $block..."
  dd if="$block" of="$workdir/vendor_boot.orig" bs=1048576 || \
    abort "Dumping vendor_boot failed. Aborting..."

  ui_print " " "Replacing vendor_boot DLKM modules and DTB..."
  "$BIN/vendor_boot_repack" "$workdir/vendor_boot.orig" "$dlkm_fragment" \
    "$dtb_file" "$AKHOME/vendor_boot.img" || abort "Repacking vendor_boot v4 failed. Aborting..."

}

apply_superfloppy() {
  local mode=$1
  local new_hex mode_name

  # Hex values for superfloppy (hardcoded)
  # -1: superfloppy=-1 -> 7375706572666c6f7070793d2d31
  #  0: superfloppy=0  -> 7375706572666c6f7070793d30
  #  1: superfloppy=1  -> 7375706572666c6f7070793d31
  #  2: superfloppy=2  -> 7375706572666c6f7070793d32
  #  3: superfloppy=3  -> 7375706572666c6f7070793d33
  #  4: superfloppy=4  -> 7375706572666c6f7070793d34
  #  5: superfloppy=5  -> 7375706572666c6f7070793d35

  case "$mode" in
    1) new_hex="7375706572666c6f7070793d31"; mode_name="Enabler" ;;
    2) new_hex="7375706572666c6f7070793d32"; mode_name="MegaFloppy (2.6 GHz)" ;;
    3) new_hex="7375706572666c6f7070793d33"; mode_name="UltraFloppy (2.7 GHz)" ;;
    4) new_hex="7375706572666c6f7070793d34"; mode_name="CoolFloppy (2.112 GHz cap)" ;;
    5) new_hex="7375706572666c6f7070793d35"; mode_name="BalancedFloppy (CL0 2.2 GHz)" ;;
    *) return 1 ;;
  esac

  [ -f "$AKHOME/Image" ] || return 0

  log_feat "Unlocked mode: setting superfloppy=$mode ($mode_name)"

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

    [ "$old_val" = "$mode" ] && continue

    $BIN/magiskboot hexpatch "$AKHOME/Image" "$old_hex" "$new_hex" 2>/dev/null
    if [ $? -eq 0 ]; then
      log_feat "superfloppy: patched ($old_val -> $mode)"
      patch_success=1
      break
    fi
  done

  if [ "$patch_success" -eq 0 ]; then
    if hexdump -C "$AKHOME/Image" 2>/dev/null | grep -qi "$new_hex" 2>/dev/null; then
      log_feat "superfloppy: already set to $mode"
    else
      log_warn "superfloppy: hex patch failed! Aborting installation."
      exit 1
    fi
  fi
}

apply_force_perm() {
  local hex_0="666f7263655f7065726d3d30"
  local hex_1="666f7263655f7065726d3d31"

  [ -f "$AKHOME/Image" ] || return 0

  $BIN/magiskboot hexpatch "$AKHOME/Image" "$hex_0" "$hex_1" >/dev/null 2>&1
}

apply_ems_efficient() {
  local hex_0="656d735f656666696369656e743d30"
  local hex_1="656d735f656666696369656e743d31"

  [ -f "$AKHOME/Image" ] || return 0

  $BIN/magiskboot hexpatch "$AKHOME/Image" "$hex_0" "$hex_1" >/dev/null 2>&1
}

apply_init_debug() {
  local mode=$1
  local hex_0="696e69745f64656275673d30"
  local hex_1="696e69745f64656275673d31"
  local target_hex="$hex_0"

  case "$mode" in
    1) target_hex="$hex_1" ;;
    *) target_hex="$hex_0" ;;
  esac

  [ -f "$AKHOME/Image" ] || return 0

  $BIN/magiskboot hexpatch "$AKHOME/Image" "$hex_0" "$target_hex" >/dev/null 2>&1
  $BIN/magiskboot hexpatch "$AKHOME/Image" "$hex_1" "$target_hex" >/dev/null 2>&1
}

apply_mali_version() {
  local target=$1
  local new_hex mode_name

  case "$target" in
    r32p1) new_hex="6d616c692e76657273696f6e3d7233327031"; mode_name="r32p1" ;;
    r38p1) new_hex="6d616c692e76657273696f6e3d7233387031"; mode_name="r38p1" ;;
    r44p1) new_hex="6d616c692e76657273696f6e3d7234347031"; mode_name="r44p1" ;;
    *) return 1 ;;
  esac

  [ -f "$AKHOME/Image" ] || return 0

  log_feat "Mali version: restoring $mode_name"

  patch_success=0
  for old_val in r32p1 r38p1 r44p1; do
    [ "$old_val" = "$target" ] && continue

    case "$old_val" in
      r32p1) old_hex="6d616c692e76657273696f6e3d7233327031" ;;
      r38p1) old_hex="6d616c692e76657273696f6e3d7233387031" ;;
      r44p1) old_hex="6d616c692e76657273696f6e3d7234347031" ;;
    esac

    $BIN/magiskboot hexpatch "$AKHOME/Image" "$old_hex" "$new_hex" 2>/dev/null
    if [ $? -eq 0 ]; then
      log_feat "mali.version: patched ($old_val -> $target)"
      patch_success=1
      break
    fi
  done

  if [ "$patch_success" -eq 0 ]; then
    if hexdump -C "$AKHOME/Image" 2>/dev/null | grep -qi "$new_hex" 2>/dev/null; then
      log_feat "mali.version: already set to $mode_name"
    else
      log_warn "mali.version: hex patch failed! Aborting installation."
      exit 1
    fi
  fi
}

# Check if /cache is mounted, try to mount if not
cache_mounted=0;
if mountpoint -q /cache 2>/dev/null; then
  cache_mounted=1;
else
  if mount /cache 2>/dev/null; then
    cache_mounted=1;
  fi
fi

# Check for feature flags in /cache/fk_feat
superfloppy_mode=-1;
mali_version="";
if [ "$cache_mounted" -eq 1 ] && [ -f /cache/fk_feat ]; then
  superfloppy_line=$(grep "^superfloppy=" /cache/fk_feat 2>/dev/null | head -1)
  if [ -n "$superfloppy_line" ]; then
    superfloppy_mode=$(echo "$superfloppy_line" | cut -d'=' -f2)
    if [ "$superfloppy_mode" != "1" ] && [ "$superfloppy_mode" != "2" ] && [ "$superfloppy_mode" != "3" ] && [ "$superfloppy_mode" != "4" ] && [ "$superfloppy_mode" != "5" ]; then
      superfloppy_mode=-1
    fi
  fi

  mali_version_line=$(grep "^mali.version=" /cache/fk_feat 2>/dev/null | head -1)
  if [ -n "$mali_version_line" ]; then
    mali_version=$(echo "$mali_version_line" | cut -d'=' -f2)
  fi
fi

if [ "$superfloppy_mode" -ge 1 ] && [ "$superfloppy_mode" -le 5 ]; then
  log_feat "Unlocked mode: enabled (mode $superfloppy_mode)"
  apply_superfloppy "$superfloppy_mode"
else
  log_feat "Unlocked mode: disabled"
fi

if [ "$cache_mounted" -eq 1 ] && [ -f /cache/fk_feat ] && grep -q "force_perm" /cache/fk_feat 2>/dev/null; then
  log_feat "Permissive mode: enabled"
  apply_force_perm
  if [ $? -eq 0 ]; then
    log_feat "force_perm: patched (0 -> 1)"
  else
    log_warn "force_perm: hex patch failed! Aborting installation."
    exit 1
  fi
fi

if [ "$cache_mounted" -eq 1 ] && [ -f /cache/fk_feat ] && grep -q "ems_efficient" /cache/fk_feat 2>/dev/null; then
  log_feat "EMS efficient mode: enabled"
  apply_ems_efficient
  if [ $? -eq 0 ]; then
    log_feat "ems_efficient: patched (0 -> 1)"
  else
    log_warn "ems_efficient: hex patch failed! Aborting installation."
    exit 1
  fi
fi

if [ "$cache_mounted" -eq 1 ] && [ -f /cache/fk_feat ] && grep -q "init_debug=" /cache/fk_feat 2>/dev/null; then
  val=$(grep -o 'init_debug=[0-9]*' /cache/fk_feat | head -n1 | cut -d= -f2)
  case "$val" in
    1)
      log_feat "InitDebug: enabled"
      apply_init_debug "$val"
      ;;
    0)
      apply_init_debug "$val"
      ;;
  esac
elif [ "$cache_mounted" -eq 1 ] && [ -f /cache/fk_feat ] && grep -q "init_debug" /cache/fk_feat 2>/dev/null; then
  log_feat "InitDebug: enabled"
  apply_init_debug 1
fi

# Restore mali.version if saved in /cache/fk_feat
if [ -n "$mali_version" ]; then
  apply_mali_version "$mali_version"
fi

# Detect ROM type and patch aosp_mode accordingly
detect_aosp_mode

# boot install
dump_boot; # use split_boot to skip ramdisk unpack, e.g. for devices with init_boot ramdisk

write_boot; # use flash_boot to skip ramdisk repack, e.g. for devices with init_boot ramdisk
## end boot install

repack_vendor_boot_modules
# Flash modified image
flash_generic vendor_boot;
