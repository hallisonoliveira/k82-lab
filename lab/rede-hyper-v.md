# Criar a rede do laboratório no Hyper-V

Este guia configura uma rede privada para as VMs do laboratório Kubernetes, com acesso entre elas, comunicação com o Windows host e saída para a internet.

## Topologia

Use um **switch interno** do Hyper-V e um NAT no Windows:

```text
                         Internet
                            |
                    Windows host (NAT)
                    vEthernet (K8sLab)
                     192.168.50.1/24
                            |
                 Switch interno K8sLab
                   /        |         \
             k8s-cp01  worker01   worker02 / sre-tools
              .10        .11         .12 / .20
```

O Windows atua como gateway NAT. O switch interno permite que o host e as VMs conversem; o NAT permite que as VMs iniciem conexões para fora. Não é necessário criar uma ponte direta para a rede física. Por padrão, conexões iniciadas da rede doméstica para as VMs não são encaminhadas automaticamente.

## Requisitos

- Windows Pro ou Enterprise com Hyper-V habilitado e privilégios de administrador.
- Um prefixo privado livre, sem sobreposição com sua rede doméstica, VPN ou redes de Pods/Services do Kubernetes. Este exemplo usa `192.168.50.0/24`; troque-o se já estiver em uso.
- VMs conectadas a um adaptador de rede virtual ligado ao switch `K8sLab`.

Confira no PowerShell elevado se o recurso está disponível:

```powershell
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
Get-VMSwitch
```

Se o Hyper-V ainda não estiver habilitado, use **Ativar ou desativar recursos do Windows** ou siga o procedimento oficial da Microsoft para sua edição. Reinicie se o Windows solicitar.

## 1. Criar o switch interno

Abra o PowerShell **como Administrador**. Crie o switch e atribua ao adaptador virtual do host o endereço do gateway:

```powershell
New-VMSwitch -Name 'K8sLab' -SwitchType Internal
New-NetIPAddress `
  -InterfaceAlias 'vEthernet (K8sLab)' `
  -IPAddress 192.168.50.1 `
  -PrefixLength 24
```

Se o switch já existir, confira seu estado antes de tentar criá-lo de novo:

```powershell
Get-VMSwitch -Name 'K8sLab'
Get-NetIPAddress -InterfaceAlias 'vEthernet (K8sLab)' -AddressFamily IPv4
```

O endereço `.1` fica reservado para o host/gateway. Não o atribua a uma VM.

## 2. Criar o NAT

```powershell
New-NetNat -Name 'K8sLabNAT' -InternalIPInterfaceAddressPrefix '192.168.50.0/24'
Get-NetNat -Name 'K8sLabNAT'
```

O cmdlet `New-NetNat` é uma operação do host e requer uma sessão elevada. Em algumas configurações, o Windows permite apenas uma rede NAT interna por host. Se já houver NAT para outro laboratório, consulte `Get-NetNat` e escolha uma solução compatível antes de alterar o existente.

Para conferir o NAT:

```powershell
Get-NetNat | Format-Table Name, InternalIPInterfaceAddressPrefix
```

## 3. Conectar as VMs ao switch

Para VMs existentes, desligue-as e conecte o adaptador ao switch:

```powershell
Connect-VMNetworkAdapter -VMName 'k8s-cp01' -SwitchName 'K8sLab'
Connect-VMNetworkAdapter -VMName 'k8s-worker01' -SwitchName 'K8sLab'
Connect-VMNetworkAdapter -VMName 'k8s-worker02' -SwitchName 'K8sLab'
Connect-VMNetworkAdapter -VMName 'sre-tools' -SwitchName 'K8sLab'
```

Se as VMs ainda não existem, selecione `K8sLab` no campo **Virtual switch** ao criar o adaptador de rede. Confirme a ligação:

```powershell
Get-VMNetworkAdapter -VMName 'k8s-cp01','k8s-worker01','k8s-worker02','sre-tools' |
  Format-Table VMName, SwitchName, Status
```

Se uma VM tiver adaptadores adicionais, defina qual interface será usada pelo Kubernetes e configure suas rotas/IPs de forma explícita. Para o começo, uma única interface nesta rede simplifica o ambiente.

## 4. Configurar IPs nas VMs

Este exemplo usa endereços estáticos. Configure a interface de cada VM (por exemplo, pelo Netplan no Ubuntu Server) com:

| Máquina | IPv4 | Prefixo | Gateway | DNS |
| --- | --- | --- | --- | --- |
| Windows host | `192.168.50.1` | `/24` | — | DNS atual do host |
| `k8s-cp01` | `192.168.50.10` | `/24` | `192.168.50.1` | `1.1.1.1`, `8.8.8.8` |
| `k8s-worker01` | `192.168.50.11` | `/24` | `192.168.50.1` | `1.1.1.1`, `8.8.8.8` |
| `k8s-worker02` | `192.168.50.12` | `/24` | `192.168.50.1` | `1.1.1.1`, `8.8.8.8` |
| `sre-tools` | `192.168.50.20` | `/24` | `192.168.50.1` | `1.1.1.1`, `8.8.8.8` |

O uso dos resolvedores públicos é apenas um exemplo. Você pode usar DNS de sua rede, desde que as VMs consigam consultá-lo. Não configure o endereço do host `.1` como DNS: o NAT não fornece serviço DNS.

Exemplo de Netplan para `k8s-cp01` (o nome da interface, aqui `eth0`, pode ser diferente; confirme com `ip link`):

```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - 192.168.50.10/24
      routes:
        - to: default
          via: 192.168.50.1
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
```

Salve, por exemplo, em `/etc/netplan/50-k8slab.yaml` e aplique no console da VM:

```bash
sudo netplan try
sudo netplan apply
ip -4 addr
ip route
```

`netplan try` permite reverter a configuração se a conexão cair; no primeiro ajuste, prefira o console do Hyper-V em vez de depender de SSH.

## 5. Validar a rede

Em cada VM, valide primeiro o gateway e depois o acesso externo:

```bash
ping -c 3 192.168.50.1
ping -c 3 192.168.50.11   # troque pelo IP de outro nó
getent hosts kubernetes.io
curl -I https://kubernetes.io
```

No Windows, valide os endereços e o switch:

```powershell
Get-NetIPAddress -InterfaceAlias 'vEthernet (K8sLab)' -AddressFamily IPv4
Get-VMSwitch -Name 'K8sLab'
```

O `ping` pode estar bloqueado por firewall mesmo quando a conectividade TCP funciona. Se ele falhar, confirme IP, prefixo, rota e firewall; teste também SSH entre VMs ou outro serviço TCP. Para o laboratório Kubernetes, confirme comunicação direta entre todos os nós e resoluções DNS funcionando.

## 6. Endereços para o Kubernetes

Use os endereços `192.168.50.10–12` para a comunicação entre os nós. Ao executar `kubeadm init`, escolha um CIDR de Pods que não se sobreponha a `192.168.50.0/24`, à rede doméstica ou à VPN; por exemplo, `10.244.0.0/16`, se estiver livre e de acordo com a configuração do CNI. A rede de Services também deve ser distinta.

Configure os nomes dos nós para resolverem de forma consistente, por DNS interno ou em `/etc/hosts` em todas as VMs, por exemplo:

```text
192.168.50.10 k8s-cp01
192.168.50.11 k8s-worker01
192.168.50.12 k8s-worker02
192.168.50.20 sre-tools
```

## Solução de problemas

- **Sem internet nas VMs:** confirme gateway `192.168.50.1`, prefixo `/24`, NAT em `Get-NetNat` e DNS configurado na VM.
- **VM não alcança outra VM:** confira se ambas usam o switch `K8sLab`, se estão na mesma sub-rede e se o firewall Linux permite o tráfego necessário.
- **Conflito ao criar NAT:** consulte `Get-NetNat`; não remova um NAT preexistente sem saber qual laboratório o utiliza.
- **Windows não alcança serviço da VM:** o switch interno fornece alcance do host à VM. Para tráfego iniciado por outros dispositivos da LAN, configure encaminhamento/portas conscientemente ou use outro desenho de rede.
- **CIDR já utilizado:** escolha outro bloco privado antes de inicializar o cluster e mantenha switch, IPs, Pods e Services sem sobreposição.

## Referências

- [Criar switches virtuais no Hyper-V](https://learn.microsoft.com/windows-server/virtualization/hyper-v/get-started/create-a-virtual-switch)
- [New-VMSwitch](https://learn.microsoft.com/powershell/module/hyper-v/new-vmswitch)
- [New-NetNat](https://learn.microsoft.com/powershell/module/netnat/new-netnat)
- [Configuração de rede em clusters kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
