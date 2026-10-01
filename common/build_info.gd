class_name BuildInfo
## Where this binary came from. CI (.github/workflows/build.yml) overwrites this file before
## exporting; source checkouts and local exports keep these defaults (NUMBER 0 = not a CI build,
## so the auto-updater stays off).

const REPO := "gabidorak/homersim"  ## GitHub "owner/name" the updater downloads from
const BRANCH := ""  ## git branch the build was made from
const NUMBER := 0  ## GitHub Actions run number of the Build workflow (grows with every build)
const COMMIT := ""
