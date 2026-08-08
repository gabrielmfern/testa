building this requires libnode being installed on the machine.

for linux:

```sh
sudo pacman-key --recv-keys CCED9BE21E1173C61DC1C9407931B6D628C8D3BA --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key CCED9BE21E1173C61DC1C9407931B6D628C8D3BA

printf '\n[arch4edu]\nServer = https://repository.arch4edu.org/$arch\n' | sudo tee -a /etc/pacman.conf

sudo pacman -Sy libnode
```

for macos:

```sh
brew install node
```

already comes with it installed

