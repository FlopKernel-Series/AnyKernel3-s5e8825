### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

## FloppyKernel Feature Toggle Patcher

### AnyKernel setup
# global properties
properties() { '
kernel.string=FloppyKernel Feature Patcher
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

# Read action, feature flag, feature name, and descriptions from files in the zip
ACTION=""
FEATURE_FLAG=""
FEATURE_NAME=""
COMMENT=""
GENERAL_DESC=""
VALUE_DESC=""
VALUE=""

if [ -f "$AKHOME/patcher_action" ]; then
  ACTION=$(cat "$AKHOME/patcher_action" 2>/dev/null)
fi

if [ -f "$AKHOME/patcher_feature" ]; then
  FEATURE_FLAG=$(cat "$AKHOME/patcher_feature" 2>/dev/null)
fi

if [ -f "$AKHOME/patcher_feature_name" ]; then
  FEATURE_NAME=$(cat "$AKHOME/patcher_feature_name" 2>/dev/null)
fi

if [ -f "$AKHOME/patcher_comment" ]; then
  COMMENT=$(cat "$AKHOME/patcher_comment" 2>/dev/null)
fi

if [ -f "$AKHOME/patcher_general_desc" ]; then
  GENERAL_DESC=$(cat "$AKHOME/patcher_general_desc" 2>/dev/null)
fi

if [ -f "$AKHOME/patcher_value_desc" ]; then
  VALUE_DESC=$(cat "$AKHOME/patcher_value_desc" 2>/dev/null)
fi

if [ -f "$AKHOME/patcher_value" ]; then
  VALUE=$(cat "$AKHOME/patcher_value" 2>/dev/null)
fi

RANGE_MIN=""
RANGE_MAX=""
if [ -f "$AKHOME/patcher_range_min" ]; then
  RANGE_MIN=$(cat "$AKHOME/patcher_range_min" 2>/dev/null | tr -d '\n')
fi
if [ -f "$AKHOME/patcher_range_max" ]; then
  RANGE_MAX=$(cat "$AKHOME/patcher_range_max" 2>/dev/null | tr -d '\n')
fi

if [ -z "$ACTION" ] || [ -z "$FEATURE_FLAG" ]; then
  ui_print "ERROR: Invalid patcher zip! Missing action or feature flag."
  exit 1
fi

# Use feature name if available, otherwise fall back to flag
if [ -z "$FEATURE_NAME" ]; then
  FEATURE_NAME="$FEATURE_FLAG"
fi

ui_print " "
ui_print "-> Patcher info"
ui_print "Feature: $FEATURE_NAME"
if [ "$ACTION" = "set" ]; then
  ui_print "Action: Set value"
else
  ui_print "Action: $ACTION"
fi

# Display descriptions based on type
if [ -n "$GENERAL_DESC" ]; then
  ui_print "General description: \"$GENERAL_DESC\""
fi
if [ -n "$VALUE_DESC" ]; then
  ui_print "Value description: \"$VALUE_DESC\""
elif [ -n "$COMMENT" ]; then
  ui_print "Description: \"$COMMENT\""
fi
ui_print " "

# Check if /cache is mounted, try to mount if not
cache_mounted=0;
if mountpoint -q /cache 2>/dev/null; then
  cache_mounted=1;
else
  ui_print "Mounting /cache..."
  if mount /cache 2>/dev/null; then
    cache_mounted=1;
  else
    ui_print "Warning: Cannot mount /cache!"
    ui_print "Your choice will NOT be saved."
    ui_print "Please ensure /cache partition is accessible."
    ui_print "Continuing anyway..."
  fi
fi

# Read patch hex values from files in the zip
PATCH_OLD=""
PATCH_NEW=""

if [ -f "$AKHOME/patcher_patch_old" ]; then
  PATCH_OLD=$(cat "$AKHOME/patcher_patch_old" 2>/dev/null | tr -d '\n')
fi

if [ -f "$AKHOME/patcher_patch_new" ]; then
  PATCH_NEW=$(cat "$AKHOME/patcher_patch_new" 2>/dev/null | tr -d '\n')
fi

if [ -z "$PATCH_OLD" ] || [ -z "$PATCH_NEW" ]; then
  ui_print "ERROR: Invalid patcher zip! Missing patch hex values."
  exit 1
fi

# Dump boot partition
dump_boot;
if [ $? != 0 ]; then
  ui_print "ERROR: Dumping boot partition failed!"
  exit 1
fi

# Find the kernel file (could be Image, kernel, kernel.gz, etc.)
KERNEL_FILE=""
if [ -f "$SPLITIMG/Image" ]; then
  KERNEL_FILE="$SPLITIMG/Image"
elif [ -f "$SPLITIMG/kernel" ]; then
  KERNEL_FILE="$SPLITIMG/kernel"
elif [ "$(ls $SPLITIMG/kernel* 2>/dev/null)" ]; then
  KERNEL_FILE=$(ls $SPLITIMG/kernel* | grep -v 'kernel_dtb' | tail -n1)
elif [ "$(ls $SPLITIMG/Image* 2>/dev/null)" ]; then
  KERNEL_FILE=$(ls $SPLITIMG/Image* | tail -n1)
fi

if [ -z "$KERNEL_FILE" ] || [ ! -f "$KERNEL_FILE" ]; then
  ui_print "ERROR: Could not extract kernel Image from boot partition!"
  ui_print "Checked: $SPLITIMG/Image, $SPLITIMG/kernel, and other kernel files"
  exit 1
fi

# Patch the kernel Image
PATCH_SUCCESS=0
SKIP_WRITE_BOOT=0

# Check if this is an int type (has range) or bool type
IS_INT_TYPE=0
if [ -n "$GENERAL_DESC" ] && [ -n "$RANGE_MIN" ] && [ -n "$RANGE_MAX" ]; then
  IS_INT_TYPE=1
fi

if [ "$IS_INT_TYPE" -eq 1 ]; then
  # For int types, try multiple old values based on the defined range
  # Try -1 first (default state), then 0 (reserved), then 1-127

  # Try -1 first (default/disabled state)
  PATCH_OLD_TRY=$(echo -n "${FEATURE_FLAG}=-1" | xxd -p | tr -d '\n' 2>/dev/null)
  if [ -n "$PATCH_OLD_TRY" ] && [ -n "$PATCH_NEW" ]; then
    $BIN/magiskboot hexpatch "$KERNEL_FILE" \
      "$PATCH_OLD_TRY" \
      "$PATCH_NEW" 2>/dev/null
    if [ $? -eq 0 ]; then
      PATCH_SUCCESS=1
    fi
  fi

  # If not successful, try 0 (reserved/transition state)
  if [ "$PATCH_SUCCESS" -eq 0 ]; then
    PATCH_OLD_TRY=$(echo -n "${FEATURE_FLAG}=0" | xxd -p | tr -d '\n' 2>/dev/null)
    if [ -n "$PATCH_OLD_TRY" ] && [ -n "$PATCH_NEW" ]; then
      $BIN/magiskboot hexpatch "$KERNEL_FILE" \
        "$PATCH_OLD_TRY" \
        "$PATCH_NEW" 2>/dev/null
      if [ $? -eq 0 ]; then
        PATCH_SUCCESS=1
      fi
    fi
  fi

  # If not successful, try values 1 to RANGE_MAX
  if [ "$PATCH_SUCCESS" -eq 0 ] && [ "$RANGE_MAX" -ge 1 ]; then
    i=1
    while [ "$i" -le "$RANGE_MAX" ] 2>/dev/null; do
      PATCH_OLD_TRY=$(echo -n "${FEATURE_FLAG}=${i}" | xxd -p | tr -d '\n' 2>/dev/null)
      if [ -n "$PATCH_OLD_TRY" ] && [ -n "$PATCH_NEW" ]; then
        $BIN/magiskboot hexpatch "$KERNEL_FILE" \
          "$PATCH_OLD_TRY" \
          "$PATCH_NEW" 2>/dev/null
        if [ $? -eq 0 ]; then
          PATCH_SUCCESS=1
          break
        fi
      fi
      # Increment using arithmetic expansion for better compatibility
      i=$((i + 1))
    done
  fi
else
  # For bool types, use the provided old value (pre-generated in zip)
  if [ -n "$PATCH_OLD" ] && [ -n "$PATCH_NEW" ]; then
    $BIN/magiskboot hexpatch "$KERNEL_FILE" \
      "$PATCH_OLD" \
      "$PATCH_NEW"
    if [ $? -eq 0 ]; then
      PATCH_SUCCESS=1
    fi
  fi
fi

if [ "$PATCH_SUCCESS" -eq 0 ]; then
  # Check if the patch failed because it's already in the desired state
  # Convert hex pattern to binary and search for it in the kernel file
  PATCH_NEW_BIN=$(echo "$PATCH_NEW" | xxd -r -p 2>/dev/null)
  ALREADY_PATCHED=0
  if [ -n "$PATCH_NEW_BIN" ]; then
    # Search for the binary pattern in the kernel file
    if grep -qF "$PATCH_NEW_BIN" "$KERNEL_FILE" 2>/dev/null; then
      ALREADY_PATCHED=1
    fi
  else
    # Fallback: check hex pattern directly in hexdump output
    if hexdump -C "$KERNEL_FILE" 2>/dev/null | grep -qi "$PATCH_NEW" 2>/dev/null; then
      ALREADY_PATCHED=1
    fi
  fi

  if [ "$ALREADY_PATCHED" -eq 1 ]; then
    if [ "$ACTION" = "enable" ]; then
      ui_print "Feature is already enabled."
    elif [ "$ACTION" = "set" ]; then
      ui_print "Feature is already set to this value."
    elif [ "$ACTION" = "disable" ]; then
      ui_print "Feature is already disabled."
    fi
    ui_print "No changes needed."
    # Skip writing boot partition since no changes were made
    # Still need to update /cache flag, so continue
    SKIP_WRITE_BOOT=1
  else
    ui_print "ERROR: Kernel hex patching failed!"
    exit 1
  fi
else
  ui_print "Kernel patched successfully."
  SKIP_WRITE_BOOT=0
fi

# Write boot partition back (only if we actually patched it)
if [ "$SKIP_WRITE_BOOT" != "1" ]; then
  write_boot;
  if [ $? -ne 0 ]; then
    ui_print "ERROR: Writing boot partition failed!"
    exit 1
  fi
fi

# Save feature flag to /cache/fk_feat for future kernel installations
if [ "$cache_mounted" -eq 1 ]; then
  # Read existing feature flags or create empty file
  FEAT_FILE="/cache/fk_feat"
  if [ -f "$FEAT_FILE" ]; then
    FEATURES=$(cat "$FEAT_FILE" 2>/dev/null)
  else
    FEATURES=""
  fi

  if [ "$ACTION" = "enable" ]; then
    # Add feature flag if not already present (bool type)
    if ! echo "$FEATURES" | grep -q "^$FEATURE_FLAG$" 2>/dev/null; then
      # Append feature flag (one per line)
      if [ -n "$FEATURES" ]; then
        echo "$FEATURES" > "$FEAT_FILE"
        echo "$FEATURE_FLAG" >> "$FEAT_FILE"
      else
        echo "$FEATURE_FLAG" > "$FEAT_FILE"
      fi
      ui_print " "
      ui_print "Feature flag saved to /cache/fk_feat."
    else
      # Flag already exists, but still confirm it's saved
      ui_print " "
      ui_print "Feature flag already saved in /cache/fk_feat."
    fi
  elif [ "$ACTION" = "set" ]; then
    # Set feature flag with value (int type)
    FLAG_ENTRY="${FEATURE_FLAG}=${VALUE}"
    # Remove any existing entry for this flag (with any value)
    NEW_FEATURES=$(echo "$FEATURES" | grep -v "^${FEATURE_FLAG}=" 2>/dev/null || true)
    # Add the new entry
    if [ -n "$NEW_FEATURES" ]; then
      echo "$NEW_FEATURES" > "$FEAT_FILE"
      echo "$FLAG_ENTRY" >> "$FEAT_FILE"
    else
      echo "$FLAG_ENTRY" > "$FEAT_FILE"
    fi
    ui_print " "
    ui_print "Feature flag saved to /cache/fk_feat."
  elif [ "$ACTION" = "disable" ]; then
    if [ -n "$GENERAL_DESC" ]; then
      # Int type disable - set to -1
      FLAG_ENTRY="${FEATURE_FLAG}=-1"
      # Remove any existing entry for this flag (with any value)
      NEW_FEATURES=$(echo "$FEATURES" | grep -v "^${FEATURE_FLAG}=" 2>/dev/null || true)
      # Add the -1 entry
      if [ -n "$NEW_FEATURES" ]; then
        echo "$NEW_FEATURES" > "$FEAT_FILE"
        echo "$FLAG_ENTRY" >> "$FEAT_FILE"
      else
        echo "$FLAG_ENTRY" > "$FEAT_FILE"
      fi
      ui_print " "
      ui_print "Feature flag set to disabled in /cache/fk_feat."
    else
      # Bool type disable - remove feature flag
      if echo "$FEATURES" | grep -q "^$FEATURE_FLAG$" 2>/dev/null; then
        # Remove the line containing the feature flag
        echo "$FEATURES" | grep -v "^$FEATURE_FLAG$" > "$FEAT_FILE"
        ui_print " "
        ui_print "Feature flag removed from /cache/fk_feat."
      else
        # Flag already removed, but still confirm
        ui_print " "
        ui_print "Feature flag already removed from /cache/fk_feat."
      fi
    fi
  fi
else
  ui_print "Warning: Could not save feature flag to /cache (not accessible)."
  if [ "$SKIP_WRITE_BOOT" != "1" ]; then
    ui_print "The current kernel has been patched, but the flag won't persist for future installations."
  else
    ui_print "The flag won't persist for future installations."
  fi
fi

ui_print " "
ui_print "Please reboot for changes to take effect."
