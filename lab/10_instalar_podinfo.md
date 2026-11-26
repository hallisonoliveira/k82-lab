# Instalar e validar o podinfo

Esta etapa instala uma aplicação pequena para os exercícios iniciais de Kubernetes e SRE. O `podinfo` fornece interface HTTP, endpoints de saúde e métricas, e será usado para observar Pods, Services, rollouts e recuperação.

Execute os comandos em `sre-tools`, com o `kubectl` e o Helm configurados. Pré-requisitos: etapas [8 — adicionar workers](8-adicionar_workers.md) e [9 — configurar acesso ao cluster](9-configurar_acesso_cluster_sre_tools.md) concluídas. Confirme que os três nós estão `Ready` e que o Metrics Server não é necessário para este exercício inicial.

## 10.1 Conferir o cluster e instalar Helm

Antes de alterar o cluster, confira o contexto e os nós:

```bash
kubectl config current-context
kubectl get nodes -o wide
kubectl get pods -A
```

O contexto esperado é `k8s-lab-admin`. Se o Helm ainda não estiver instalado, instale o Helm 3 em `sre-tools` usando o script oficial:

```bash
sudo apt-get update
sudo apt-get install -y curl
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

O script instala o Helm no sistema e requer `sudo` para disponibilizar o executável. Confirme a instalação e a versão:

```bash
helm version
```

## 10.2 Criar os valores do podinfo

Crie `podinfo-values.yaml` no diretório de trabalho de `sre-tools`:

```yaml
replicaCount: 2

service:
  type: NodePort
  nodePort: 31198

resources:
  requests:
    cpu: 100m
    memory: 64Mi
  limits:
    cpu: 500m
    memory: 256Mi

hpa:
  enabled: false
```

Neste primeiro exercício, o HPA fica desabilitado para manter duas réplicas estáveis e isolar o comportamento do Deployment. O NodePort permite acessar o serviço pelo IP de um worker na porta `31198`, desde que a rede e o firewall do host permitam essa conexão.

## 10.3 Instalar a aplicação

Adicione o repositório Helm oficial e instale o chart no namespace `lab-sre`:

```bash
helm repo add podinfo https://stefanprodan.github.io/podinfo
helm repo update
helm upgrade --install podinfo podinfo/podinfo \
  --namespace lab-sre \
  --create-namespace \
  --values podinfo-values.yaml \
  --wait --timeout 5m
```

O `upgrade --install` cria a release na primeira execução e atualiza a mesma release em execuções posteriores. O arquivo de valores fica na VM e não contém credenciais.

## 10.4 Validar Deployment, Service e acesso HTTP

Confira os recursos e a distribuição dos Pods:

```bash
kubectl get deployment,replicaset,pods,service -n lab-sre -o wide
kubectl rollout status deployment/podinfo -n lab-sre --timeout=5m
kubectl get endpointslices -n lab-sre
```

Devem existir duas réplicas prontas e o Service deve ter endpoints correspondentes aos Pods prontos. Teste a partir de `sre-tools`:

```bash
curl -i http://<IP_DE_UM_WORKER>:31198/
curl -i http://<IP_DE_UM_WORKER>:31198/healthz
curl -i http://<IP_DE_UM_WORKER>:31198/readyz
```

Também é possível abrir `http://<IP_DE_UM_WORKER>:31198/` no Windows. Use o IP de um worker acessível a partir do host. Se a conexão falhar, confirme `kubectl get service -n lab-sre`, o IP do worker, a rota e as regras de firewall; não altere probes ou reinicie os nós sem evidência de que o problema está no cluster.

### Critério para avançar

- A release `podinfo` está implantada no namespace `lab-sre`.
- O Deployment tem duas réplicas disponíveis e os Pods estão `Ready`.
- O Service NodePort aponta para endpoints prontos.
- Os endpoints HTTP respondem a partir de `sre-tools` ou do Windows.

Referências: [chart oficial do podinfo](https://github.com/stefanprodan/podinfo/tree/master/charts/podinfo), [repositório do podinfo](https://github.com/stefanprodan/podinfo) e [Helm: upgrade](https://helm.sh/docs/helm/helm_upgrade/).
