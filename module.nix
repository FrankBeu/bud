{ name, config, lib, pkgs, hostConfig, editableFlakeRoot, ... }:
with lib;
let
  cfg = config.bud;
  entryOptions = {
    enable = mkEnableOption "cmd" // { default = true; };

    synopsis = mkOption {
      type = types.str;
      description = ''
        Synopsis.
      '';
    };
    help = mkOption {
      type = types.str;
      description = ''
        Short help.
      '';
    };
    description = mkOption {
      type = types.str;
      default = "";
      description = ''
        Longer descriptions.
      '';
    };

    writer = mkOption {
      type = types.functionTo (types.functionTo types.package);
      description = ''
        Script to run.
      '';
    };

    script = mkOption {
      type = types.path;
      description = ''
        Script to run.
      '';
    };

    deps = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        A list of other commands that this one should be cuaranteed to be placed after.
      '';
    };
  };

  addUsage =
    mapAttrs (k: v: builtins.removeAttrs v [ "script" "enable" "synopsis" "help" "description" ] // {
      text = ''
        "${v.synopsis}" "${v.help}" \'';
    });

  addCase =
    mapAttrs (k: v: builtins.removeAttrs v [ "script" "enable" "synopsis" "help" "description" ] // {
      text =
        let
          script' = v.writer (builtins.baseNameOf v.script) v.script;
        in
        ''
          # ${k} subcommand
          "${k}")
            shift 1;
            mkcmd "${v.synopsis}" "${v.help}" "${v.description}" "${script'}" "$@"
            ;;

        '';
    });

  arch = pkgs.system;

  host =
    let
      partitionString = sep: s:
        builtins.filter (v: builtins.isString v) (builtins.split "${sep}" s);
      reversePartition = s: lib.reverseList (partitionString "\\." s);
      rebake = l: builtins.concatStringsSep "." l;
    in
    if (hostConfig != null && hostConfig.networking.domain != null) then
      rebake (reversePartition hostConfig.networking.domain ++ [ hostConfig.networking.hostName ])
    else if hostConfig != null then
      hostConfig.networking.hostName
    # fall back to reverse dns from hostname --fqdn command
    else "$(IFS='.'; parts=($(hostname --fqdn)); IFS=' '; HOST=$(for (( idx=\${#parts[@]}-1 ; idx>=0 ; idx-- )) ; do printf \"\${parts[idx]}.\"; done); echo \${HOST:: -1})"
  ;

  flakeRoot =
    if editableFlakeRoot != null
    then editableFlakeRoot
    else "$PRJ_ROOT"
  ;

  ### TODO create colorModule -> extract
  BR = "\u001b[30m";    ### Black
  CR = "\u001b[36m";    ### Cyan    Reg   category
  GR = "\u001b[32m";    ### Green   Reg   success,good
  MR = "\u001b[35m";    ### Magenta Reg
  RR = "\u001b[31m";    ### Red     Reg   error,danger,stop
  UR = "\u001b[34m";    ### blUe    Reg   stability,calm
  WR = "\u001b[37m";    ### White   Reg
  YR = "\u001b[33m";    ### Yellow  Reg   proceed with caution,warning, in progress
  BB = "\u001b[30;1m";  ### Black   Bold
  CB = "\u001b[36;1m";  ### Cyan    Bold
  GB = "\u001b[32;1m";  ### Green   Bold  success,good
  MB = "\u001b[35;1m";  ### Magenta Bold
  RB = "\u001b[31;1m";  ### Red     Bold  error,danger,stop
  UB = "\u001b[34;1m";  ### blUe    Bold  stability,calm
  WB = "\u001b[37;1m";  ### White   Bold
  YB = "\u001b[33;1m";  ### Yellow  Bold  proceed with caution,warning, in progress
  NE = "\u001b[0m";     ### NoEffects

  ### WORKAROUND: indentation: multiline help-strings have to be indented in the bud-setup in DEVOS
  ### TODO:       find solution or export and use width for: printf "  %-45b %b\n\n" \
  columnWidthActual = 48;
  columnWidth       = columnWidthActual - 3 ; ### printf statements are used with 2 leading and 1 trailing space
  cw                = builtins.toString columnWidth;

  budCmd = pkgs.writeShellScriptBin name ''

    export PATH="${makeBinPath [ pkgs.coreutils pkgs.hostname ]}"

    shopt -s extglob

    FLAKEROOT="${flakeRoot}" # writable
    HOST="${host}"
    USER="$(logname)"
    ARCH="${arch}"

    # mocks: for testing onlye
    FLAKEROOT="''${TEST_FLAKEROOT:-$FLAKEROOT}"
    HOST="''${TEST_HOST:-$HOST}"
    USER="''${TEST_USER:-$USER}"
    ARCH="''${TEST_ARCH:-$ARCH}"

    # needs a FLAKEROOT
    [[ -d "$FLAKEROOT" ]] ||
      {
        echo "This script must be run either from the flake's devshell or its root path must be specified" >&2
        exit 1
      }

    # FLAKEROOT must be writable (no store path)
    [[ -w "$FLAKEROOT" ]] ||
      {
        echo "You canot use the flake's store path for reference."
             "This script requires a pointer to the writable flake root." >&2
        exit 1
      }


    mkcmd () {
      synopsis=$1
      help=$2
      description=$3
      script=$4
      shift 4;
      case "$1" in
        "-h"|"help"|"--help")
          printf "\n"
          printf "  %b\n\n"                    \
                 "\${UB}Usage\${NE}:"
          printf "  %-${cw}b %b\n"             \
                 "''${synopsis}" "''${help}\n"
          printf "\n  %b\n\n"                  \
                 "\${UB}Description\${NE}:"
          printf "  %b\n\n"                    \
                 "$description"
          ;;
        *)
          FLAKEROOT="$FLAKEROOT" HOST="$HOST" USER="$USER" ARCH="$ARCH" exec $script "$@"
          ;;
      esac
    }

    usage () {
    printf "%b\n"                         \
      ""                                  \
      "  \${UB}Usage\${NE}: "             \
      ""                                  \
      "  $(basename $0) COMMAND [ARGS]\n" \
      ""                                  \
      "  \${UB}Commands\${NE}:"           \
      ""                                  \

    printf "  %-${cw}b %b\n\n" \
    ${textClosureMap id (addUsage cfg.cmds) (attrNames cfg.cmds)}

    }

    case "$1" in
    ""|"-h"|"help"|"--help")
      usage
      ;;

    ${textClosureMap id (addCase cfg.cmds) (attrNames cfg.cmds)}
    esac
  '';
in
{
  options.bud = {
    cmds = mkOption {
      type = types.attrsOf (types.nullOr (types.submodule { options = entryOptions; }));
      default = { };
      internal = true;
      apply = as: filterAttrs (_: v: v.enable == true) as;
      description = ''
        A list of sub commands appended to the `bud` case switch statement.
      '';
    };
    cmd = mkOption {
      internal = true;
      type = types.package;
      description = ''
        This package contains the fully resolved `bud` script.
      '';
    };
  };

  config.bud = {
    cmd = budCmd;
  };
}
