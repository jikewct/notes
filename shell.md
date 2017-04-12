# shell

- 获取当前脚本的绝对路径
http://stackoverflow.com/questions/59895/getting-the-source-directory-of-a-bash-script-from-within
short ans: DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
note: 不能直接用basename，因为可能会直接得到.
