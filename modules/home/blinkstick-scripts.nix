{
  config.flake.homeModules.blinkstick-scripts = {
    pkgs,
    lib,
    ...
  }: let
    blinkStickPkg = pkgs.python3Packages.buildPythonPackage rec {
      pname = "blinkstick";
      version = "1.2";

      src = pkgs.fetchFromGitHub {
        owner = "arvydas";
        repo = "blinkstick-python";
        rev = "8140b9fa18a9ff4f0e9df8e70c073f41cb8f1d35";
        sha256 = "02qfjvbinjid1hp5chi5ms3wpvfkbphnl2rcvdwwz5f87x63pdzm";
      };

      propagatedBuildInputs = [pkgs.python3Packages.pyusb];

      pyproject = true;
      build-system = [pkgs.python3Packages.setuptools pkgs.python3Packages.setuptools-scm];
      doCheck = false;
      pythonImportsCheck = ["blinkstick"];

      meta = with lib; {
        description = "Python package to control BlinkStick USB devices";
        homepage = "https://github.com/arvydas/blinkstick-python";
        license = licenses.bsd3;
        maintainers = with maintainers; [np];
      };
    };

    scriptEnv = pkgs.python3.withPackages (_: [blinkStickPkg]);

    blinkstickScripts = pkgs.writeScriptBin "blinkstick-scripts" ''
      #!${scriptEnv.interpreter}
      from blinkstick import blinkstick
      import sys

      bstick = blinkstick.find_first()

      if bstick is not None:
          num_leds = bstick.get_led_count()

          if sys.argv[1] == 'white':
              led_data = [255, 255, 255] * num_leds
          elif sys.argv[1] == 'off':
              led_data = [0, 0, 0] * num_leds
          elif sys.argv[1] == 'red':
              led_data = [0, 255, 0] * num_leds
          elif sys.argv[1] == 'pink':
              led_data = [105, 255, 180] * num_leds
          else:
              print("Invalid argument")
              sys.exit(1)

          bstick.set_led_data(0, led_data)
      else:
          print("No BlinkSticks found...")
    '';
  in {
    home.packages = [blinkstickScripts];
  };
}
