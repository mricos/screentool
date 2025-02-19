st=$HOME/src/screentool/screentool.sh
alias st=$st
sts=$(dirname $(realpath $st))
std=$HOME/recordings
stf(){
  grep -n $1 $sts/*.sh
}

stl(){
  ls -d $std
  ls -lh $std
}

stu(){
  link=$std/latest.mp4
  [ -L "$link" ] || return
  target=$(readlink -f "$link")
  rm -f "$link" "$target"
}

stm(){
  link=$std/latest.mp4
  [ -L "$link" ] || return
  target=$(readlink -f "$link")
  ln -s "$target" $std/$1
}

