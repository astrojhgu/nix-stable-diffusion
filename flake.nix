{
  description = "Nix Flake for runnig Stable Diffusion on NixOS";

  inputs = {
    nixlib.url = "github:nix-community/nixpkgs.lib";
    nixpkgs = {
      url = "github:NixOS/nixpkgs"; #?rev=33919d25f0c873b0c73e2f8d0859fab3bd0d1b26";
    };
    stable-diffusion-repo = {
      url = "github:Stability-AI/stablediffusion?rev=47b6b607fdd31875c9279cd2f4f16b92e4ea958e";
      flake = false;
    };
    invokeai-repo = {
      url = "github:invoke-ai/InvokeAI?ref=v2.3.1.post2";
      flake = false;
    };
  };
  outputs = { self, nixpkgs, nixlib, stable-diffusion-repo, invokeai-repo }@inputs:
    let
      nixlib = inputs.nixlib.outputs.lib;
      system = "x86_64-linux";
      requirementsFor = { pkgs, webui ? false, nvidia ? false }: with pkgs; with pkgs.python3.pkgs; [
        python3
        torch
        torchvision
        numpy
        albumentations
        opencv4
        pudb
        imageio
        imageio-ffmpeg
        pytorch-lightning
        omegaconf
        test-tube
        streamlit
        protobuf
        einops
        taming-transformers-rom1504
        torch-fidelity
        torchmetrics
        transformers
        kornia
        k-diffusion
        diffusers
        # following packages not needed for vanilla SD but used by both UIs
        realesrgan
        pillow
        safetensors
      ]
      ++ nixlib.optional (nvidia) [ xformers ]
      ++ nixlib.optional (!webui) [
        npyscreen
        huggingface-hub
        dnspython
        datasets
        click
        pypatchmatch
        torchsde
        compel
        send2trash
        flask
        flask-socketio
        flask-cors
        gfpgan
        eventlet
        clipseg
        getpass-asterisk
        picklescan
      ]
      ++ nixlib.optional webui [
        addict
        future
        lmdb
        pyyaml
        scikitimage
        tqdm
        yapf
        gdown
        lpips
        fastapi
        lark
        analytics-python
        ffmpy
        markdown-it-py
        shap
        gradio
        fonts
        font-roboto
        piexif
        codeformer
        blip
        psutil
        openclip
        blendmodes
      ];
      overlay_default = nixpkgs: pythonPackages:
        {
          pytorch-lightning = pythonPackages.pytorch-lightning.overrideAttrs (old: {
            nativeBuildInputs = old.nativeBuildInputs ++ [ nixpkgs.python3Packages.pythonRelaxDepsHook ];
            pythonRelaxDeps = [ "protobuf" ];
          });
          scikit-image = pythonPackages.scikitimage;
        };
      overlay_webui = nixpkgs: pythonPackages:
        {
          transformers = pythonPackages.transformers.overrideAttrs (old: {
            src = nixpkgs.fetchFromGitHub {
              owner = "huggingface";
              repo = "transformers";
              rev = "refs/tags/v4.19.2";
              hash = "sha256-9r/1vW7Rhv9+Swxdzu5PTnlQlT8ofJeZamHf5X4ql8w=";
            };
          });
        };
      overlay_pynixify = self:
        let
          rm = d: d.overrideAttrs (old: {
            nativeBuildInputs = old.nativeBuildInputs ++ [ self.pythonRelaxDepsHook ];
            pythonRemoveDeps = [ "opencv-python-headless" "opencv-python" "tb-nightly" "clip" ];
          });
          callPackage = self.callPackage;
          rmCallPackage = path: args: rm (callPackage path args);
          mapCallPackage = pnames: builtins.listToAttrs (builtins.map (pname: { name = pname; value = (callPackage (./packages + "/${pname}") { }); }) pnames);
          simplePackages = [
            "filterpy"
            "kornia"
            "lpips"
            "ffmpy"
            "shap"
            "fonts"
            "font-roboto"
            "analytics-python"
            "markdown-it-py"
            "gradio"
            "hatch-requirements-txt"
            "timm"
            "blip"
            "fairscale"
            "torch-fidelity"
            "resize-right"
            "torchdiffeq"
            "accelerate"
            "clip-anytorch"
            "jsonmerge"
            "clean-fid"
            "getpass-asterisk"
            "pypatchmatch"
            "trampoline"
            "torchsde"
            "compel"
            "diffusers"
            "safetensors"
            "picklescan"
            "openclip"
            "blendmodes"
            "xformers"
            "pyre-extensions"
            # "triton" nixpkgs is missing required llvm parts - mlir
          ];
        in
        {
          pydeprecate = callPackage ./packages/pydeprecate { };
          taming-transformers-rom1504 =
            callPackage ./packages/taming-transformers-rom1504 { };
          albumentations = rmCallPackage ./packages/albumentations { opencv-python-headless = self.opencv4; };
          qudida = rmCallPackage ./packages/qudida { opencv-python-headless = self.opencv4; };
          gfpgan = rmCallPackage ./packages/gfpgan { opencv-python = self.opencv4; };
          basicsr = rmCallPackage ./packages/basicsr { opencv-python = self.opencv4; };
          facexlib = rmCallPackage ./packages/facexlib { opencv-python = self.opencv4; };
          codeformer = callPackage ./packages/codeformer { opencv-python = self.opencv4; };
          realesrgan = rmCallPackage ./packages/realesrgan { opencv-python = self.opencv4; };
          clipseg = rmCallPackage ./packages/clipseg { opencv-python = self.opencv4; };
          k-diffusion = callPackage ./packages/k-diffusion { clean-fid = self.clean-fid; };
        } // mapCallPackage simplePackages;
      overlay_amd = nixpkgs: pythonPackages:
        rec {
          #IMPORTANT: you can browse available wheels on the server, but only if you add trailing "/" - e.g. https://download.pytorch.org/whl/rocm5.2/
          torch-bin = pythonPackages.torch-bin.overrideAttrs (old: {
            src = nixpkgs.fetchurl {
              name = "torch-1.13.1+rocm5.2-cp310-cp310-linux_x86_64.whl";
              url = "https://download.pytorch.org/whl/rocm5.2/torch-1.13.1%2Brocm5.2-cp310-cp310-linux_x86_64.whl";
              hash = "sha256-82hdCKwNjJUcw2f5vUsskkxdRRdmnEdoB3SKvNlmE28=";
            };
          });
          torchvision-bin = pythonPackages.torchvision-bin.overrideAttrs (old: {
            src = nixpkgs.fetchurl {
              name = "torchvision-0.14.1+rocm5.2-cp310-cp310-linux_x86_64.whl";
              url = "https://download.pytorch.org/whl/rocm5.2/torchvision-0.14.1%2Brocm5.2-cp310-cp310-linux_x86_64.whl";
              hash = "sha256-oBYG/K7bgkxu0UvmyS2U1ud2LkFQ/CarcxpEJ9xzMYQ=";
            };
          });
          torch = torch-bin;
          torchvision = torchvision-bin;
        };
      overlay_nvidia = nixpkgs: pythonPackages:
        {
          torch = pythonPackages.torch-bin;
          torchvision = pythonPackages.torchvision-bin;
        };
    in
    let
      mkShell = inputs.nixpkgs.legacyPackages.${system}.mkShell;
      nixpkgs_ = { amd ? false, nvidia ? false, webui ? false }:
        import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = nvidia; #CUDA is unfree.
          overlays = [
            (final: prev:
              let
                optional = nixlib.optionalAttrs;
                sl = (prev.streamlit.override ({ protobuf3 = prev.protobuf; }));
                makePythonHook = args: final.makeSetupHook ({ passthru.provides.setupHook = true; } // args);
                pythonRelaxDepsHook = prev.callPackage
                  ({ wheel }:
                    makePythonHook
                      {
                        name = "python-relax-deps-hook";
                        propagatedBuildInputs = [ wheel ];
                        substitutions = {
                          pythonInterpreter = nixlib.getExe prev.python3Packages.python;
                        };
                      } ./python-relax-deps-hook.sh)
                  { wheel = prev.python3.pkgs.wheel; };
              in
              {
                inherit pythonRelaxDepsHook;
                streamlit = sl.overrideAttrs (old: {
                  nativeBuildInputs = old.nativeBuildInputs ++ [ pythonRelaxDepsHook ];
                  pythonRemoveDeps = [ "protobuf" ];
                });
                python3 = prev.python3.override {
                  packageOverrides =
                    python-self: python-super:
                    (overlay_default prev python-super) //
                    optional amd (overlay_amd prev python-super) //
                    optional nvidia (overlay_nvidia prev python-super) //
                    optional webui (overlay_webui prev python-super) //
                    (overlay_pynixify python-self);
                };
              })
          ];
        } // { inherit nvidia; };
    in
    {
      packages.${system} =
        let
          nixpkgs = (nixpkgs_ { });
          nixpkgsAmd = (nixpkgs_ { amd = true; });
          nixpkgsNvidia = (nixpkgs_ { nvidia = true; });
          invokeaiF = nixpkgs: nixpkgs.python3.pkgs.buildPythonPackage {
            pname = "invokeai";
            version = "2.3.1";
            src = invokeai-repo;
            format = "pyproject";
            propagatedBuildInputs = requirementsFor { pkgs = nixpkgs; nvidia = nixpkgs.nvidia; };
            nativeBuildInputs = [ nixpkgs.pkgs.pythonRelaxDepsHook ];
            pythonRelaxDeps = [ "torch" "pytorch-lightning" "flask-socketio" "flask" "dnspython" ];
            pythonRemoveDeps = [ "opencv-python" "flaskwebgui" "pyreadline3" ];
          };
        in
        {
          invokeai = {
            amd = invokeaiF nixpkgsAmd;
            nvidia = invokeaiF nixpkgsNvidia;
            default = invokeaiF nixpkgs;
          };
        };
      devShells.${system} =
        {
          webui =
            let
              shellHookFor = nixpkgs:
                let
                  submodel = pkg: nixpkgs.pkgs.python3.pkgs.${pkg} + "/lib/python3.10/site-packages";
                  taming-transformers = submodel "taming-transformers-rom1504";
                  k_diffusion = submodel "k-diffusion";
                  codeformer = (submodel "codeformer") + "/codeformer";
                  blip = (submodel "blip") + "/blip";
              joinedModels = nixpkgs.symlinkJoin { name = "webui-models"; paths = [ inputs.stable-diffusion-repo taming-transformers k_diffusion codeformer blip ]; };
                in
                ''
                  cd stable-diffusion-webui
                  #git reset --hard HEAD
                  #git apply ${./webui.patch}
                  rm -rf repositories/
                  mkdir repositories
                  pushd repositories
                  ln -s ${inputs.stable-diffusion-repo}/ stable-diffusion-stability-ai
                  ln -s ${taming-transformers}/ taming-transformers
                  ln -s ${k_diffusion}/ k-diffusion
                  ln -s ${codeformer}/ CodeFormer
                  ln -s ${blip}/ BLIP
                  popd
                  /* substituteInPlace modules/paths.py \ */
                  /*   --subst-var-by taming_transformers ${taming-transformers} \ */
                  /*   --subst-var-by k_diffusion ${k_diffusion} \ */
                  /*   --subst-var-by codeformer ${codeformer} \ */
                  /*   --subst-var-by blip ${blip} */
                '';
            in
            {
              default = mkShell
                (
                  let args = { pkgs = (nixpkgs_ { webui = true; }); webui = true; }; in
                  {
                    shellHook = shellHookFor args.pkgs;
                    name = "webui";
                    propagatedBuildInputs = requirementsFor args.pkgs;
                  }
                );
              amd = mkShell
                (
                  let args = { pkgs = (nixpkgs_ { webui = true; amd = true; }); webui = true; }; in
                  {
                    shellHook = shellHookFor args.pkgs;
                    name = "webui.amd";
                    propagatedBuildInputs = requirementsFor args;
                  }
                );
              nvidia = mkShell
                (
                  let args = { pkgs = (nixpkgs_ { webui = true; nvidia = true; }); webui = true; }; in
                  {
                    shellHook = shellHookFor args.pkgs;
                    name = "webui.nvidia";
                    propagatedBuildInputs = requirementsFor args;
                  }
                );
            };
        };
    };
}
