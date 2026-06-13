{
  description = "Toshy - Mac-style keybindings for Linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ 
      "x86_64-linux" 
      "aarch64-linux"
      # Note: macOS support would require significant changes to xwaykeyz
      # "x86_64-darwin" 
      # "aarch64-darwin"
    ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = nixpkgs.lib;
        
        # Platform-specific configurations
        platformConfig = {
          x86_64-linux = {
            # Optimizations for x86_64
            enableOptimizations = true;
            supportedCompositors = [ "hyprland" "sway" "wlroots" "gnome" "kde" ];
            supportedWindowManagers = [ "i3" "bspwm" "xmonad" "gnome" "kde" "xfce" ];
          };
          aarch64-linux = {
            # ARM-specific optimizations
            enableOptimizations = false; # More conservative for ARM
            supportedCompositors = [ "sway" "wlroots" "gnome" ];
            supportedWindowManagers = [ "i3" "gnome" "xfce" ];
          };
        };
        
        currentPlatform = platformConfig.${system} or platformConfig.x86_64-linux;
        python = pkgs.python3;
        
        # Custom python-xlib 0.31 to avoid conflicts
        pythonXlib031 = python.pkgs.xlib.overrideAttrs (oldAttrs: rec {
          version = "0.31";
          src = pkgs.fetchPypi {
            pname = "python-xlib";
            version = "0.31";
            hash = "sha256-dNg6CB9TK8B/bXr81kFuw4QD1o9oubncnh8o+/LXmek=";
          };
        });

        # Custom xwaykeyz package (main dependency not in nixpkgs)
        xwaykeyz = python.pkgs.buildPythonPackage rec {
          pname = "xwaykeyz";
          version = "1.2.0";
          format = "pyproject";

          src = pkgs.fetchFromGitHub {
            owner = "RedBearAK";
            repo = "xwaykeyz";
            rev = "7bd5a58f5b00733182e3fc9f2dcee8efa8c7cd03";
            hash = "sha256-1QfO25F+X9Qb1YbfIv0a86C8rKNVzWSrRhPHIzOjDbw=";
          };

          nativeBuildInputs = with python.pkgs; [
            hatchling
          ];

          propagatedBuildInputs = with python.pkgs; [
            appdirs
            dbus-python
            evdev
            i3ipc
            inotify-simple
            ordered-set
            pywayland
            pythonXlib031
          ] ++ pkgs.lib.optionals (python.pkgs ? hyprpy) [
            python.pkgs.hyprpy
          ];

          # Skip tests for now during initial setup
          doCheck = false;
          
          # Skip runtime dependency checks for now
          dontCheckRuntimeDeps = true;
          
          # Skip conflict detection - we know about the python-xlib version conflict
          catchConflicts = false;

          meta = with pkgs.lib; {
            description = "A fork of keyszer for X11 and Wayland";
            homepage = "https://github.com/RedBearAK/xwaykeyz";
            license = licenses.gpl3Plus;
            maintainers = [ ];
            platforms = platforms.linux;
          };
        };

        # Main Toshy package
        toshy = python.pkgs.buildPythonApplication rec {
          pname = "toshy";
          version = "24.12.1";
          format = "pyproject";

          src = ./.;

          nativeBuildInputs = with pkgs; [
            wrapGAppsHook3
            gobject-introspection
            procps # For pgrep, pkill commands needed by configuration
          ] ++ (with python.pkgs; [
            setuptools
            wheel
          ]);

          buildInputs = with pkgs; [
            gtk3
            gtk4  # Add GTK4 for modern GUI
            gobject-introspection
            libappindicator-gtk3  # For system tray support
            libayatana-appindicator # Alternative AppIndicator implementation
            libnotify # For notify-send command
            libadwaita # Modern GTK4 styling
            gsettings-desktop-schemas # GTK4 schemas
          ];

          propagatedBuildInputs = with python.pkgs; [
            # Standard nixpkgs packages
            appdirs
            dbus-python
            evdev
            i3ipc
            inotify-simple
            lockfile
            ordered-set
            pillow
            psutil
            pygobject3
            pywayland
            six
            # python-systemd: renamed systemd -> systemd-python in newer nixpkgs
            (python.pkgs.systemd-python or python.pkgs.systemd)
            watchdog  # File system monitoring
            
            # Use the same python-xlib version as xwaykeyz
            pythonXlib031
            
            # Custom packages
            xwaykeyz
          ] ++ pkgs.lib.optionals (python.pkgs ? hyprpy) [
            python.pkgs.hyprpy
          ] ++ pkgs.lib.optionals (python.pkgs ? sv-ttk) [
            python.pkgs.sv-ttk
          ] ++ pkgs.lib.optionals (python.pkgs ? xkbcommon) [
            python.pkgs.xkbcommon
          ];

          # Enable tests and add test dependencies
          doCheck = true;
          
          nativeCheckInputs = with python.pkgs; [
            pytest
            pytest-cov
            pytest-mock
          ];
          
          checkPhase = ''
            runHook preCheck
            
            # Run tests
            python -m pytest tests/ -v
            
            runHook postCheck
          '';
          
          # Skip runtime dependency checks for now
          dontCheckRuntimeDeps = true;
          
          # Skip conflict detection
          catchConflicts = false;

          # KDE Plasma (KWin) window-context integration. Upstream's
          # setup_toshy.py installs these imperatively and setuptools
          # package-data does not cover them, so install them here:
          #   - the KWin script that reports the focused window's class over
          #     D-Bus (discovered by KWin via XDG_DATA_DIRS), and
          #   - the D-Bus service that owns org.toshy.Plasma, wrapped as the
          #     toshy-kwin-dbus executable used by the NixOS module.
          postInstall = ''
            kwinScriptDir=$out/share/kwin/scripts/toshy-dbus-notifyactivewindow
            mkdir -p "$kwinScriptDir"
            cp -r ${./kwin-script/kde5_kde6_merged/toshy-dbus-notifyactivewindow}/. "$kwinScriptDir"/

            install -Dm644 ${./kwin-dbus-service/toshy_kwin_dbus_service.py} \
              "$out/${python.sitePackages}/toshy_kwin_dbus_service.py"
            makeWrapper ${python.interpreter} "$out/bin/toshy-kwin-dbus" \
              --add-flags "$out/${python.sitePackages}/toshy_kwin_dbus_service.py" \
              --prefix PYTHONPATH : "$out/${python.sitePackages}:$PYTHONPATH"
          '';

          meta = with pkgs.lib; {
            description = "Mac-style keybindings for Linux";
            homepage = "https://github.com/celesrenata/toshy";
            license = licenses.gpl3Plus;
            maintainers = [ ];
            platforms = platforms.linux;
            mainProgram = "toshy-tray";
          };
        };

      in {
        packages = {
          inherit toshy xwaykeyz;
          default = toshy;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            python3
            python3Packages.pip
            python3Packages.setuptools
            python3Packages.wheel
            
            # Testing tools
            python3Packages.pytest
            python3Packages.pytest-cov
            python3Packages.pytest-mock
            python3Packages.black
            python3Packages.flake8
            
            # Performance monitoring
            python3Packages.psutil
            
            # Development tools
            nixpkgs-fmt
            git
            
            # System dependencies for development
            gtk3
            gobject-introspection
            pkg-config
            
            # Cross-compilation tools
            gcc
            binutils
          ] ++ lib.optionals (system == "x86_64-linux") [
            # x86_64 specific tools
            gdb
            valgrind
          ] ++ lib.optionals (system == "aarch64-linux") [
            # ARM specific tools
            # Add ARM-specific debugging tools if needed
          ];

          shellHook = ''
            echo "Toshy development environment (${system})"
            echo "Python: $(python --version)"
            echo "Platform: ${builtins.concatStringsSep ", " currentPlatform.supportedCompositors}"
            echo ""
            echo "Available commands:"
            echo "  - nixpkgs-fmt: Format Nix files"
            echo "  - nix build: Build the package"
            echo "  - nix run: Run toshy"
            echo "  - pytest: Run tests"
            echo "  - black: Format Python code"
            echo "  - flake8: Lint Python code"
            echo ""
            echo "New Phase 4 tools:"
            echo "  - toshy-platform: Platform detection"
            echo "  - toshy-debug: Comprehensive diagnostics"
            echo "  - toshy-performance: Performance monitoring"
            echo ""
            echo "Testing:"
            echo "  - pytest tests/: Run all tests"
            echo "  - pytest tests/test_config.py: Run specific test file"
            echo "  - pytest --cov=toshy tests/: Run tests with coverage"
            echo ""
            echo "Cross-compilation:"
            echo "  - nix build .#packages.aarch64-linux.toshy: Build for ARM64"
            echo "  - nix flake check --all-systems: Check all platforms"
          '';
        };

        formatter = pkgs.nixpkgs-fmt;
      }
    ) // {
      # NixOS module
      nixosModules.toshy = import ./modules/toshy.nix;
      nixosModules.default = self.nixosModules.toshy;
      
      # Home Manager module
      homeManagerModules.toshy = import ./home-manager/toshy.nix;
      homeManagerModules.default = self.homeManagerModules.toshy;
      
      # Overlay for easy integration
      overlays.default = final: prev: {
        toshy = self.packages.${prev.system}.toshy;
        xwaykeyz = self.packages.${prev.system}.xwaykeyz;
      };
    };
}
