### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=FloppyKernel (6.6 edition) v1.0.0 for Exynos 1280 devices by @Flopster101
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
supported.versions=15.0-17.0
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

FK_FEAT=/cache/fk_feat
FK_DEF=/vendor/etc/fkdef
FK_VAL=""
FK_SRC=""

fk_cache_has() {
  [ "$cache_mounted" = "1" ] && [ -f "$FK_FEAT" ] && grep -q "$1" "$FK_FEAT" 2>/dev/null
}

fk_def_has() {
  [ -f "$FK_DEF" ] && grep -q "$1" "$FK_DEF" 2>/dev/null
}

fk_resolve_num() {
  local key="$1" v=""
  if [ "$cache_mounted" = "1" ] && [ -f "$FK_FEAT" ]; then
    v=$(grep -o "${key}=[0-9]*" "$FK_FEAT" 2>/dev/null | head -n1 | cut -d= -f2)
    if [ -n "$v" ]; then FK_VAL="$v"; FK_SRC="fk_feat"; return 0; fi
  fi
  if [ -f "$FK_DEF" ]; then
    v=$(grep -o "${key}=[0-9]*" "$FK_DEF" 2>/dev/null | head -n1 | cut -d= -f2)
    if [ -n "$v" ]; then FK_VAL="$v"; FK_SRC="fkdef"; return 0; fi
  fi
  return 1
}

fk_resolve_flag() {
  local key="$1" bare_def="$2" v=""
  if [ "$cache_mounted" = "1" ] && [ -f "$FK_FEAT" ] && grep -q "$key" "$FK_FEAT" 2>/dev/null; then
    v=$(grep -o "${key}=[0-9]*" "$FK_FEAT" 2>/dev/null | head -n1 | cut -d= -f2)
    if [ -n "$v" ]; then FK_VAL="$v"; else FK_VAL="$bare_def"; fi
    FK_SRC="fk_feat"
    return 0
  fi
  if [ -f "$FK_DEF" ] && grep -q "$key" "$FK_DEF" 2>/dev/null; then
    v=$(grep -o "${key}=[0-9]*" "$FK_DEF" 2>/dev/null | head -n1 | cut -d= -f2)
    if [ -n "$v" ]; then FK_VAL="$v"; else FK_VAL="$bare_def"; fi
    FK_SRC="fkdef"
    return 0
  fi
  return 1
}

fk_resolve_str() {
  local key="$1" v=""
  if [ "$cache_mounted" = "1" ] && [ -f "$FK_FEAT" ]; then
    v=$(grep "^${key}=" "$FK_FEAT" 2>/dev/null | head -n1 | cut -d= -f2)
    if [ -n "$v" ]; then FK_VAL="$v"; FK_SRC="fk_feat"; return 0; fi
  fi
  if [ -f "$FK_DEF" ]; then
    v=$(grep "^${key}=" "$FK_DEF" 2>/dev/null | head -n1 | cut -d= -f2)
    if [ -n "$v" ]; then FK_VAL="$v"; FK_SRC="fkdef"; return 0; fi
  fi
  return 1
}

fk_tag() { [ "$FK_SRC" = "fkdef" ] && echo " (fkdef)" || echo ""; }

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

# Check if /cache is mounted, try to mount if not
cache_mounted=0;
if mountpoint -q /cache 2>/dev/null; then
  cache_mounted=1;
else
  if mount /cache 2>/dev/null; then
    cache_mounted=1;
  fi
fi

# Check for feature flags in /cache/fk_feat and /vendor/etc/fkdef
if ! grep -q ' /vendor ' /proc/mounts 2>/dev/null; then
  mount -o ro /vendor 2>/dev/null || mount -o ro /dev/block/mapper/vendor /vendor 2>/dev/null
fi

if [ -f "$FK_DEF" ]; then
  log_rom "ROM defaults: $FK_DEF detected"
fi

# fkfeat handlers are wired here as features land in the 6.6 kernel.

# boot install
dump_boot; # use split_boot to skip ramdisk unpack, e.g. for devices with init_boot ramdisk

write_boot; # use flash_boot to skip ramdisk repack, e.g. for devices with init_boot ramdisk
## end boot install

repack_vendor_boot_modules
# Flash modified image
flash_generic vendor_boot;

# flash the DTBO overlay image for this device
if [ -f "$AKHOME/dtbo.img" ]; then
  flash_generic dtbo;
else
  log_warn "dtbo.img not found in zip, keeping the stock DTBO";
fi
