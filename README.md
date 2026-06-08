# OrbStack Ubuntu Tailscale SSH Kurulumu

Bu repo, macOS uzerinde OrbStack icinde calisan Ubuntu VM'e Tailscale uzerinden terminal ve VS Code Remote - SSH ile erismek icin tek komutluk kurulum scripti saglar.

Amac:

- VM'e baska cihazdan ve baska agdan erismek.
- Router/modem uzerinde port forward yapmamak.
- SSH portunu internete acmamak.
- VS Code Remote - SSH ile VM icindeki dosya ve projelerde calisabilmek.

## Kisa Cevap

Evet, mumkun.

Baska cihaz ayni Tailscale agina, yani ayni tailnet'e, dahilse Ubuntu VM'in Tailscale IP adresine SSH ile baglanabilir:

```bash
ssh kullanici@100.x.y.z
```

VS Code Remote - SSH icin en uyumlu cozum OpenSSH server kurmaktir. Tailscale port acma ihtiyacini ortadan kaldirir, ama VS Code Remote - SSH uzaktaki makinede calisan bir SSH server bekler.

OrbStack'in kendi SSH sunucusu `ssh orb` icin cok kullanisli olsa da, OrbStack dokumanina gore sadece `localhost` baglantilarini kabul eder. Baska cihazdan dogrudan erisim icin Linux machine icine kendi SSH server'inizi kurmaniz gerekir.

## Mimari

```text
Baska cihaz
  -> Tailscale istemcisi
  -> Tailnet sifreli ag
  -> OrbStack Ubuntu VM Tailscale IP
  -> OpenSSH server
  -> Terminal veya VS Code Remote - SSH
```

Bu akista modem/router uzerinde 22/tcp portu acilmaz. Script, VM icinde UFW ile SSH'i `tailscale0` arayuzune izinli, diger arayuzlere kapali hale getirir.

## Tek Komut

Repo GitHub'a publish edildikten sonra Ubuntu VM icinde sunu calistirin:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/orbstack-ubuntu-tailscale-ssh/main/scripts/setup-tailscale-ssh.sh | bash
```

Auth key ile tam otomatik kurulum:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/orbstack-ubuntu-tailscale-ssh/main/scripts/setup-tailscale-ssh.sh | TS_AUTHKEY=tskey-auth-xxxxx TAILSCALE_HOSTNAME=orbstack-ubuntu bash
```

Not: `TS_AUTHKEY` degerini public repo'ya veya loglara yazmayin. Komut gecmisinde gorunmesini istemiyorsaniz once `read -s TS_AUTHKEY && export TS_AUTHKEY` kullanin, sonra `curl ... | bash` calistirin.

## Yerel Calistirma

```bash
bash scripts/setup-tailscale-ssh.sh
```

Script `sudo` isteyebilir.

## Script Ne Yapar?

- Ubuntu oldugunu kontrol eder.
- `ca-certificates`, `curl`, `openssh-server` ve `ufw` paketlerini kurar.
- Tailscale'i resmi Linux kurulum scripti ile kurar.
- `tailscale up` calistirir.
- `TS_AUTHKEY` verilirse interaktif login gerektirmeden tailnet'e ekler.
- OpenSSH servisini etkinlestirir.
- SSH config snippet'i olusturur.
- Istenirse SSH password login'i kapatir.
- `~/.ssh/authorized_keys` dosyasina public key ekleyebilir.
- UFW ile 22/tcp'yi sadece `tailscale0` arayuzunden kabul eder.
- Baglanti komutlarini yazdirir.

## Degiskenler

| Degisken | Varsayilan | Aciklama |
| --- | --- | --- |
| `TS_AUTHKEY` | bos | Tailscale auth key. Verilmezse `tailscale up` login URL'i basar. |
| `TAILSCALE_HOSTNAME` | mevcut hostname | Tailscale cihaz adi. |
| `TARGET_USER` | `sudo` kullanan kullanici | SSH key eklenecek Linux kullanicisi. |
| `SSH_PUBLIC_KEY` | bos | `authorized_keys` icine eklenecek public key. |
| `GITHUB_USER` | bos | `https://github.com/USER.keys` uzerinden public key import eder. |
| `AUTHORIZED_KEYS_FILE` | bos | Yerel bir authorized keys dosyasindan key ekler. |
| `IMPORT_MAC_ED25519_KEY` | `true` | OrbStack icinde `/mnt/mac/Users/$USER/.ssh/id_ed25519.pub` varsa ekler. |
| `DISABLE_PASSWORD_AUTH` | `false` | `true` ise SSH password login'i kapatir. Once key eklediginizden emin olun. |
| `LOCKDOWN_SSH_TO_TAILSCALE` | `true` | UFW ile SSH'i sadece Tailscale arayuzune kisitlar. |
| `FORCE_LOCKDOWN` | `false` | Script non-Tailscale SSH oturumundan calisiyorsa bile firewall kisitini uygular. |
| `ENABLE_TAILSCALE_SSH` | `false` | Ek olarak Tailscale SSH'i etkinlestirir. VS Code icin gerekli degildir. |

## Onerilen Kurulum

1. Tailscale admin panelinden reusable olmayan veya kisa omurlu bir auth key olusturun.
2. Baska cihazda SSH key yoksa olusturun:

```bash
ssh-keygen -t ed25519
```

3. Ubuntu VM icinde scripti calistirin. Public key'inizi dogrudan vermek icin:

```bash
TS_AUTHKEY=tskey-auth-xxxxx \
TAILSCALE_HOSTNAME=orbstack-ubuntu \
SSH_PUBLIC_KEY='ssh-ed25519 AAAA... sizin-keyiniz' \
DISABLE_PASSWORD_AUTH=true \
bash scripts/setup-tailscale-ssh.sh
```

4. Script sonunda yazan Tailscale IP adresini not edin.

5. Baska cihazda Tailscale'e girin ve test edin:

```bash
ssh kullanici@100.x.y.z
```

## VS Code Remote - SSH

Baska cihazda:

1. Tailscale kurun ve ayni tailnet'e login olun.
2. VS Code kurun.
3. `Remote - SSH` eklentisini kurun.
4. Terminalden once SSH test edin:

```bash
ssh kullanici@100.x.y.z
```

5. Lokal `~/.ssh/config` dosyasina ekleyin:

```sshconfig
Host orbstack-ubuntu
  HostName 100.x.y.z
  User kullanici
  Port 22
  IdentityFile ~/.ssh/id_ed25519
```

6. VS Code icinde `Remote-SSH: Connect to Host...` komutunu calistirin ve `orbstack-ubuntu` host'unu secin.

MagicDNS aciksa `HostName` olarak Tailscale cihaz adini da kullanabilirsiniz.

## Tailscale SSH vs OpenSSH

Tailscale SSH terminal erisimi icin guzel bir secenek olabilir ve Tailscale ACL'leri ile kimlerin SSH yapabilecegini yonetir. Ancak VS Code Remote - SSH, Microsoft dokumanina gore uzaktaki hostta calisan bir SSH server ister. Bu nedenle bu repo VS Code hedefi icin OpenSSH server kurar.

`ENABLE_TAILSCALE_SSH=true` ile Tailscale SSH'i de acabilirsiniz, ama VS Code icin bunu gerekli kabul etmeyin. Sorun yasarsaniz klasik OpenSSH + Tailscale IP yolunu kullanin.

## Guvenlik Notlari

- `TS_AUTHKEY` gizlidir; public repo'ya yazmayin.
- SSH password login'i kapatmadan once public key ile giris test edin.
- UFW kuralini script uygular: `tailscale0` uzerinden 22/tcp allow, diger 22/tcp deny.
- Tailscale ACL'leri ile hangi cihaz ve kullanicilarin VM'e erisecegini sinirlayin.
- OrbStack ayarlarinda `Expose ports to LAN` aciksa, `0.0.0.0` dinleyen servisler LAN'dan gorunebilir. Bu script SSH icin UFW kisiti uygular.

## Kontrol Komutlari

Ubuntu VM icinde:

```bash
tailscale status
tailscale ip -4
systemctl status ssh
sudo ufw status verbose
```

Baska cihazda:

```bash
tailscale status
ssh -v kullanici@100.x.y.z
```

## Sorun Giderme

SSH timeout:

- Baska cihaz Tailscale'e login mi?
- VM `tailscale status` icinde online mi?
- `sudo ufw status verbose` icinde `tailscale0` allow kuralini goruyor musunuz?
- Tailscale ACL'leri 22/tcp erisimine izin veriyor mu?

Permission denied:

- Dogru Linux kullanici adini kullaniyor musunuz?
- Public key VM'de `~/.ssh/authorized_keys` icinde mi?
- `~/.ssh` izni `700`, `authorized_keys` izni `600` mu?

VS Code baglanamiyor:

- Once terminalden `ssh kullanici@100.x.y.z` calistirin.
- VS Code Remote - SSH config dosyasinda `HostName`, `User`, `IdentityFile` dogru mu?
- VM'de en az 1 GB RAM var mi? VS Code Remote - SSH remote server kurar.

## Kaynaklar

- Tailscale Linux install: https://tailscale.com/docs/install/linux
- Tailscale SSH Linux VM rehberi: https://tailscale.com/docs/how-to/connect-ssh-linux-vm
- Tailscale SSH: https://tailscale.com/docs/features/tailscale-ssh
- OrbStack SSH access: https://docs.orbstack.dev/machines/ssh
- OrbStack Linux networking: https://docs.orbstack.dev/machines/network
- Ubuntu OpenSSH server: https://documentation.ubuntu.com/server/how-to/security/openssh-server/
- VS Code Remote - SSH: https://code.visualstudio.com/docs/remote/ssh
