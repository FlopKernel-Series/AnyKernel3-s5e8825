### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=FloppyKernel v5.5 for Exynos 1280 devices by @Flopster101
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

# boot install
dump_boot; # use split_boot to skip ramdisk unpack, e.g. for devices with init_boot ramdisk

write_boot; # use flash_boot to skip ramdisk repack, e.g. for devices with init_boot ramdisk
## end boot install

flash_generic vendor_boot;

