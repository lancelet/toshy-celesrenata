{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.toshy;

  # KDE Plasma (KWin) window-context integration. On Wayland, per-application
  # keymaps need the focused window's class, which Toshy obtains via a KWin
  # script that pushes window changes to a D-Bus service. This is active only
  # when the configured Wayland compositor is KDE/KWin.
  kdeEnabled = cfg.wayland.enable && cfg.wayland.compositor == "kde";
  kwinScriptName = "toshy-dbus-notifyactivewindow";

  # Generate configuration file content
  generateToshyConfig = {
    baseConfig = ''
      # Generated Toshy configuration
      # This file is managed by NixOS - do not edit manually
      
      import os
      import sys
      from pathlib import Path
      
      # Add the default config to Python path
      sys.path.insert(0, str(Path(__file__).parent))
      
      # Import base configuration
      try:
          from toshy_config_base import *
      except ImportError:
          # Fallback to minimal config if base not found
          from xwaykeyz.models import *
          
      # NixOS-managed configuration overrides
    '';
    
    macStyleConfig = optionalString cfg.keybindings.macStyle ''
      
      # Mac-style keybindings enabled
      ENABLE_MAC_STYLE_KEYBINDINGS = True
      
      # Common Mac-style shortcuts
      keymap("General", {
          # Text editing
          C("a"): C("ctrl-a"),          # Select all
          C("c"): C("ctrl-c"),          # Copy
          C("v"): C("ctrl-v"),          # Paste
          C("x"): C("ctrl-x"),          # Cut
          C("z"): C("ctrl-z"),          # Undo
          C("shift-z"): C("ctrl-y"),    # Redo
          
          # Navigation
          C("left"): C("home"),         # Beginning of line
          C("right"): C("end"),         # End of line
          C("up"): C("ctrl-home"),      # Beginning of document
          C("down"): C("ctrl-end"),     # End of document
          
          # Window management
          C("w"): C("ctrl-w"),          # Close window/tab
          C("t"): C("ctrl-t"),          # New tab
          C("shift-t"): C("ctrl-shift-t"), # Reopen closed tab
          C("tab"): C("ctrl-tab"),      # Next tab
          C("shift-tab"): C("ctrl-shift-tab"), # Previous tab
          
          # System shortcuts
          C("space"): C("alt-f2"),      # Application launcher
          C("q"): C("alt-f4"),          # Quit application
      })
    '';
    
    applicationConfigs = concatStringsSep "\n" (mapAttrsToList (appName: bindings: ''
      
      # Application-specific bindings for ${appName}
      keymap("${appName}", {
      ${concatStringsSep ",\n" (mapAttrsToList (from: to: 
        "    \"${from}\": \"${to}\"") bindings)}
      })
    '') cfg.keybindings.applications);
    
    customConfig = optionalString (cfg.config != "") ''
      
      # Custom user configuration
      ${cfg.config}
    '';
  };
  
  # Complete configuration content
  toshyConfigContent = concatStringsSep "\n" [
    generateToshyConfig.baseConfig
    generateToshyConfig.macStyleConfig
    generateToshyConfig.applicationConfigs
    generateToshyConfig.customConfig
  ];

in {
  options.services.toshy = {
    enable = mkEnableOption "Toshy keybinding service";
    
    package = mkPackageOption pkgs "toshy" { };
    
    user = mkOption {
      type = types.str;
      description = "User to run Toshy service as";
      example = "alice";
    };
    
    config = mkOption {
      type = types.lines;
      default = "";
      description = "Custom Toshy configuration (Python code)";
      example = ''
        # Custom keybindings
        keymap("Terminal", {
            C("c"): C("shift-c"),  # Copy in terminal
            C("v"): C("shift-v"),  # Paste in terminal
        })
      '';
    };
    
    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to external Toshy configuration file";
      example = "/etc/toshy/custom_config.py";
    };
    
    gui = {
      enable = mkEnableOption "Toshy GUI components";
      
      tray = mkEnableOption "System tray icon";
      
      theme = mkOption {
        type = types.enum ["light" "dark" "auto"];
        default = "auto";
        description = "GUI theme preference";
      };
      
      autostart = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically start GUI components with desktop session";
      };
      
      fileManager = mkOption {
        type = types.str;
        default = "thunar";
        description = "Default file manager for opening config folder";
        example = "nautilus";
      };
      
      terminal = mkOption {
        type = types.str;
        default = "foot";
        description = "Default terminal emulator for services log";
        example = "alacritty";
      };
    };
    
    keybindings = {
      macStyle = mkEnableOption "Mac-style keybindings" // { default = true; };
      
      applications = mkOption {
        type = types.attrsOf (types.attrsOf types.str);
        default = {};
        description = "Application-specific keybinding overrides";
        example = {
          "Firefox" = {
            "Cmd+T" = "Ctrl+T";  # New tab
            "Cmd+W" = "Ctrl+W";  # Close tab
          };
          "code" = {
            "Cmd+P" = "Ctrl+Shift+P";  # Command palette
          };
        };
      };
      
      globalShortcuts = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Global system shortcuts";
        example = {
          "Cmd+Space" = "Alt+F2";  # Application launcher
          "Cmd+Tab" = "Alt+Tab";   # Application switcher
        };
      };
    };
    
    wayland = {
      enable = mkEnableOption "Wayland support";
      
      compositor = mkOption {
        type = types.enum ["hyprland" "sway" "wlroots" "kde" "auto"];
        default = "auto";
        description = ''
          Wayland compositor to integrate with. Use "kde" for KDE Plasma
          (KWin), which installs and runs the KWin window-context script and
          D-Bus service needed for per-application keymaps.
        '';
      };

      autoEnableKwinScript = mkOption {
        type = types.bool;
        default = true;
        description = ''
          When the compositor is "kde", enable the Toshy KWin script in
          kwinrc on each login (via kwriteconfig6) and ask KWin to reload.
          Set to false to manage the kwinrc
          "Plugins/${kwinScriptName}Enabled" key yourself (e.g. declaratively
          through plasma-manager).
        '';
      };

      protocols = mkOption {
        type = types.listOf types.str;
        default = ["wlr-layer-shell" "xdg-shell"];
        description = "Wayland protocols to enable";
      };
    };
    
    x11 = {
      enable = mkEnableOption "X11 support";
      
      windowManager = mkOption {
        type = types.enum ["i3" "bspwm" "xmonad" "gnome" "kde" "xfce" "auto"];
        default = "auto";
        description = "X11 window manager to integrate with";
      };
      
      displayManager = mkOption {
        type = types.enum ["gdm" "sddm" "lightdm" "auto"];
        default = "auto";
        description = "Display manager integration";
      };
    };
    
    logging = {
      level = mkOption {
        type = types.enum ["DEBUG" "INFO" "WARNING" "ERROR"];
        default = "INFO";
        description = "Logging level for Toshy services";
      };
      
      file = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Log file path (default: systemd journal)";
        example = "/var/log/toshy.log";
      };
    };
    
    security = {
      enableInputGroup = mkOption {
        type = types.bool;
        default = true;
        description = "Add user to input group for device access";
      };
      
      restrictedMode = mkOption {
        type = types.bool;
        default = false;
        description = "Run in restricted mode with minimal permissions";
      };
      
      allowedUsers = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Additional users allowed to use Toshy";
        example = ["alice" "bob"];
      };
    };
    
    performance = {
      priority = mkOption {
        type = types.int;
        default = 0;
        description = "Process priority (-20 to 19, lower = higher priority)";
      };
      
      memoryLimit = mkOption {
        type = types.str;
        default = "256M";
        description = "Memory limit for Toshy processes";
      };
      
      cpuQuota = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "CPU quota for Toshy processes";
        example = "50%";
      };
    };
  };

  config = mkIf cfg.enable {
    # Assertions for configuration validation
    assertions = [
      {
        assertion = cfg.user != "";
        message = "services.toshy.user must be specified";
      }
      {
        assertion = !(cfg.wayland.enable && cfg.x11.enable) || cfg.wayland.compositor == "auto" || cfg.x11.windowManager == "auto";
        message = "Cannot enable both specific Wayland and X11 configurations simultaneously";
      }
      {
        assertion = cfg.performance.priority >= -20 && cfg.performance.priority <= 19;
        message = "services.toshy.performance.priority must be between -20 and 19";
      }
    ];

    # System packages
    environment.systemPackages = [ cfg.package ] ++ optionals cfg.gui.enable [
      pkgs.libnotify  # For notifications
      pkgs.zenity     # For GUI dialogs
    ];
    
    # User configuration directory setup with proper permissions
    systemd.user.tmpfiles.rules = [
      "d /home/${cfg.user}/.config/toshy 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.local/share/toshy 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.cache/toshy 0755 ${cfg.user} users -"
    ] ++ optionals (cfg.configFile == null) [
      # Create generated config file
      "f /home/${cfg.user}/.config/toshy/toshy_config.py 0644 ${cfg.user} users - ${pkgs.writeText "toshy-config.py" toshyConfigContent}"
    ] ++ optionals (cfg.configFile != null) [
      # Link to external config file
      "L+ /home/${cfg.user}/.config/toshy/toshy_config.py - - - - ${cfg.configFile}"
    ];

    # Main Toshy daemon service
    systemd.user.services.toshy = {
      description = "Toshy Keybinding Service";
      documentation = [ "https://github.com/celesrenata/toshy" ];
      
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ]
           ++ optionals kdeEnabled [ "toshy-kwin-dbus.service" ];

      # Service dependencies
      wants = optionals cfg.gui.enable [ "toshy-gui.service" ]
           ++ optionals cfg.gui.tray [ "toshy-tray.service" ]
           ++ optionals kdeEnabled [ "toshy-kwin-dbus.service" ];
      
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/toshy-daemon";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        
        # Restart configuration
        Restart = "always";
        RestartSec = 5;
        StartLimitBurst = 3;
        StartLimitIntervalSec = 30;
        
        # Security settings
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = false; # Need access to user config
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        
        # File system access
        ReadWritePaths = [ 
          "/home/${cfg.user}/.config/toshy"
          "/home/${cfg.user}/.local/share/toshy"
          "/home/${cfg.user}/.cache/toshy"
          # XDG_RUNTIME_DIR access is handled automatically by systemd user services
        ] ++ optionals (cfg.logging.file != null) [
          (dirOf cfg.logging.file)
        ];
        
        # Resource limits
        MemoryMax = cfg.performance.memoryLimit;
        TasksMax = 50;
        Nice = cfg.performance.priority;
      } // optionalAttrs (cfg.performance.cpuQuota != null) {
        CPUQuota = cfg.performance.cpuQuota;
      } // optionalAttrs (!cfg.security.restrictedMode) {
        # Additional permissions for full functionality
        # Note: SupplementaryGroups not supported in user services
        # User should be added to input group via users.users.${user}.extraGroups
      };
      
      environment = {
        TOSHY_CONFIG_DIR = "/home/${cfg.user}/.config/toshy";
        TOSHY_LOG_LEVEL = cfg.logging.level;
        TOSHY_USER = cfg.user;
        
        # GUI-specific environment
        TOSHY_DATA_DIR = "/home/${cfg.user}/.local/share/toshy";
        XDG_DATA_HOME = "/home/${cfg.user}/.local/share";
        XDG_CONFIG_HOME = "/home/${cfg.user}/.config";
        
        # Display environment  
        DISPLAY = ":0";
        # XDG_RUNTIME_DIR is automatically set by systemd for user services
        
        # Add procps and libnotify to PATH for system commands needed by configuration and GUI
        PATH = mkForce "${pkgs.procps}/bin:${pkgs.libnotify}/bin:${pkgs.coreutils}/bin:/etc/profiles/per-user/${cfg.user}/bin:/run/current-system/sw/bin";
        
        # GTK4 environment variables for GUI
        GI_TYPELIB_PATH = "${pkgs.gtk4}/lib/girepository-1.0:${pkgs.libadwaita}/lib/girepository-1.0:${pkgs.gobject-introspection}/lib/girepository-1.0";
        XDG_DATA_DIRS = "${pkgs.gtk4}/share:${pkgs.libadwaita}/share:${pkgs.gsettings-desktop-schemas}/share";
        GSK_RENDERER = "gl"; # Use OpenGL renderer for better performance
        
        # Ensure notify-send is available
        NOTIFY_SEND = "${pkgs.libnotify}/bin/notify-send";
      } // optionalAttrs cfg.wayland.enable {
        # Do NOT hardcode WAYLAND_DISPLAY: the compositor's socket name varies
        # per session (wayland-0, wayland-1, ...). Leaving it unset lets the unit
        # inherit the real value from the systemd user manager (populated by the
        # desktop session), so daemon.py waits on the socket that actually exists.
        XDG_SESSION_TYPE = "wayland";
      } // optionalAttrs cfg.x11.enable {
        XDG_SESSION_TYPE = "x11";
      } // optionalAttrs (cfg.logging.file != null) {
        TOSHY_LOG_FILE = cfg.logging.file;
      };
    };
    
    # GUI service (optional)
    systemd.user.services.toshy-gui = mkIf cfg.gui.enable {
      description = "Toshy GUI Service";
      documentation = [ "https://github.com/celesrenata/toshy" ];
      
      wantedBy = optionals cfg.gui.autostart [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" "toshy.service" ];
      
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/toshy-gui";
        Restart = "on-failure";
        RestartSec = 10;
        
        # Add notify-send to PATH
        Environment = "PATH=${pkgs.libnotify}/bin:${pkgs.procps}/bin:${pkgs.coreutils}/bin:/etc/profiles/per-user/${cfg.user}/bin:/run/current-system/sw/bin";
        
        # Security settings - relaxed for GUI
        NoNewPrivileges = false;  # GTK4 needs this
        PrivateTmp = false;       # GTK4 needs access to tmp
        ProtectSystem = "false";  # GTK4 needs system access
        ProtectHome = false;
        
        # Runtime directories for GTK4
        RuntimeDirectory = "toshy-gui";
        RuntimeDirectoryMode = "0755";
        
        # Resource limits
        MemoryMax = "128M";
        TasksMax = 20;
      };
      
      environment = {
        DISPLAY = ":0";
        XDG_RUNTIME_DIR = "/run/user/1000";  # Use actual user ID instead of %i
        TOSHY_THEME = cfg.gui.theme;
        TOSHY_FILE_MANAGER = cfg.gui.fileManager;
        TOSHY_TERMINAL = cfg.gui.terminal;
        # Wayland display for GTK4
        WAYLAND_DISPLAY = "wayland-1";
        XDG_SESSION_TYPE = "wayland";
        # GTK4 backend preference
        GDK_BACKEND = "wayland,x11";
        # Fix dconf permissions
        DCONF_USER_CONFIG_DIR = "/home/${cfg.user}/.config/dconf";
      } // optionalAttrs cfg.wayland.enable {
        WAYLAND_DISPLAY = "wayland-1";
      };
    };
    
    # Tray service (optional)
    systemd.user.services.toshy-tray = mkIf cfg.gui.tray {
      description = "Toshy System Tray";
      documentation = [ "https://github.com/celesrenata/toshy" ];
      
      wantedBy = optionals cfg.gui.autostart [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" "toshy.service" ];
      
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/toshy-tray";
        Restart = "on-failure";
        RestartSec = 10;
        
        # Add notify-send to PATH
        Environment = "PATH=${pkgs.libnotify}/bin:${pkgs.procps}/bin:${pkgs.coreutils}/bin:/etc/profiles/per-user/${cfg.user}/bin:/run/current-system/sw/bin";
        
        # Security settings - relaxed for tray GTK compatibility
        NoNewPrivileges = false;  # GTK needs this
        PrivateTmp = false;       # GTK needs access to tmp
        ProtectSystem = "false";  # GTK needs system access
        ProtectHome = false;
        
        # Resource limits
        MemoryMax = "64M";
        TasksMax = 10;
      };
      
      environment = {
        DISPLAY = ":0";
        XDG_RUNTIME_DIR = "/run/user/1000";  # Use actual user ID
        TOSHY_THEME = cfg.gui.theme;
        # Wayland display for GTK
        WAYLAND_DISPLAY = "wayland-1";
        XDG_SESSION_TYPE = "wayland";
        # GTK backend preference - try GTK3 first for tray compatibility
        GDK_BACKEND = "x11,wayland";
        # Fix dconf permissions
        DCONF_USER_CONFIG_DIR = "/home/${cfg.user}/.config/dconf";
      } // optionalAttrs cfg.wayland.enable {
        WAYLAND_DISPLAY = "wayland-1";
      };
    };

    # KDE Plasma window-context service: owns org.toshy.Plasma and caches the
    # focused window's class for per-application keymaps. It is fed by the KWin
    # script that ships with the package and is enabled below.
    systemd.user.services.toshy-kwin-dbus = mkIf kdeEnabled {
      description = "Toshy KWin D-Bus window-context service";
      documentation = [ "https://github.com/celesrenata/toshy" ];

      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/toshy-kwin-dbus";
        Restart = "on-failure";
        RestartSec = 5;
        MemoryMax = "64M";
        TasksMax = 10;

        # Needs pgrep (procps) for window-manager detection in env_context.py
        Environment = "PATH=${pkgs.procps}/bin:${pkgs.coreutils}/bin:/etc/profiles/per-user/${cfg.user}/bin:/run/current-system/sw/bin";
      };
    };

    # Enable the Toshy KWin script in kwinrc and ask KWin to reload it. The
    # script files ship with the package under share/kwin/scripts and are
    # discovered via XDG_DATA_DIRS, but KWin only loads them once the kwinrc
    # Plugins key is set. kwinrc is user-owned mutable state, so this is done
    # imperatively on login rather than declaratively.
    systemd.user.services.toshy-kwin-script =
      mkIf (kdeEnabled && cfg.wayland.autoEnableKwinScript) {
        description = "Enable the Toshy KWin script in kwinrc";
        documentation = [ "https://github.com/celesrenata/toshy" ];

        wantedBy = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        before = [ "toshy-kwin-dbus.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.writeShellScript "toshy-enable-kwin-script" ''
            ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 \
              --file kwinrc --group Plugins --key ${kwinScriptName}Enabled true
            ${pkgs.dbus}/bin/dbus-send --type=method_call --dest=org.kde.KWin \
              /KWin org.kde.KWin.reconfigure
          ''}";
        };
      };

    # Configuration file generation (system-wide)
    environment.etc."toshy/config.py" = mkIf (cfg.config != "" || cfg.keybindings.applications != {}) {
      text = toshyConfigContent;
      mode = "0644";
    };
    
    # Required system permissions and setup
    security.polkit.enable = true;
    
    # Input group access for evdev (if not in restricted mode)
    users.groups.input = mkIf (!cfg.security.restrictedMode) {};

    # The keymapper engine (xwaykeyz) must WRITE to /dev/uinput to synthesize
    # keystrokes. Use the stock NixOS option, which loads the uinput module,
    # creates the 'uinput' group, and ships the udev rule setting /dev/uinput to
    # mode 0660 root:uinput. Without this the engine dies with
    # "(EE) Failed to open `uinput` in write mode." and remapping never works.
    hardware.uinput.enable = true;

    # User configuration - only configure the main user.
    # 'input' grants read of /dev/input/event*; 'uinput' grants write of /dev/uinput.
    users.users.${cfg.user} = mkIf cfg.security.enableInputGroup {
      extraGroups = [ "input" "uinput" ] ++ optionals (!cfg.security.restrictedMode) [ "audio" ];
    };
    
    # Enable required services based on configuration
    services.xserver.enable = mkIf cfg.x11.enable true;
    
    # Wayland-specific setup
    programs.hyprland.enable = mkIf (cfg.wayland.enable && cfg.wayland.compositor == "hyprland") true;
    programs.sway.enable = mkIf (cfg.wayland.enable && cfg.wayland.compositor == "sway") true;
    
    # Desktop environment integration
    services.gnome.gnome-keyring.enable = mkIf (cfg.x11.windowManager == "gnome") true;
    services.displayManager.sddm.enable = mkIf (cfg.x11.displayManager == "sddm") true;
    services.xserver.displayManager.gdm.enable = mkIf (cfg.x11.displayManager == "gdm") true;
    services.xserver.displayManager.lightdm.enable = mkIf (cfg.x11.displayManager == "lightdm") true;
    
    # Logging configuration
    systemd.user.services.toshy-logger = mkIf (cfg.logging.file != null) {
      description = "Toshy Log Manager";
      wantedBy = [ "toshy.service" ];
      before = [ "toshy.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.coreutils}/bin/mkdir -p ${dirOf cfg.logging.file}";
        ExecStartPost = "${pkgs.coreutils}/bin/touch ${cfg.logging.file}";
        RemainAfterExit = true;
      };
    };
    
    # Logrotate configuration for log files
    services.logrotate.settings.toshy = mkIf (cfg.logging.file != null) {
      files = [ cfg.logging.file ];
      frequency = "weekly";
      rotate = 4;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      create = "644 ${cfg.user} users";
    };
    
    # Environment variables for all users
    environment.variables = {
      TOSHY_SYSTEM_ENABLED = "1";
    } // optionalAttrs cfg.wayland.enable {
      TOSHY_WAYLAND_ENABLED = "1";
    } // optionalAttrs cfg.x11.enable {
      TOSHY_X11_ENABLED = "1";
    };
    
    # Fonts for GUI components
    fonts.packages = mkIf cfg.gui.enable [
      pkgs.dejavu_fonts
      pkgs.liberation_ttf
    ];
  };
}
