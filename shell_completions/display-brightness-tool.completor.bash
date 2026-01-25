output=display-brightness-tool.bash
authors=('IsaacST08 (isaacshiellsthomas@me.com)')

cmd=display-brightness-tool

cmd_args='set increase decrease save restore dim undim'

cmd_opts=(
  -h --help
  --version
  -d:@words:'all,oled,non-oled'
  --display:@words:'all,oled,non-oled'
  -c --clear-cache
  -a:@words:'set,increase,decrease,save,restore,dim,undim'
  --action:@words:'set,increase,decrease,save,restore,dim,undim'
  -v:@hold
  --value:@hold
  -u --update
  -t:@hold
  --update-threshold:@hold
  -V --verbose
)
