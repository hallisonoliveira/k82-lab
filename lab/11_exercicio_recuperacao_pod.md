# Exercício: recuperação de um Pod

Neste primeiro exercício, observe como um Deployment mantém o número desejado de réplicas quando um Pod é removido. A aplicação é o `podinfo` instalado na etapa [10 — instalar podinfo](10_instalar_podinfo.md).

Execute tudo em `sre-tools`. O exercício remove deliberadamente um Pod, mas não apaga o Deployment nem a release Helm. Não use `helm uninstall`, `kubectl delete deployment` ou `kubeadm reset`.

## Objetivos

- Relacionar Deployment, ReplicaSet, Pod e Service.
- Observar a criação de um Pod substituto após a exclusão do antigo.
- Verificar se o Service continua enviando tráfego a endpoints prontos.
- Registrar duração da recuperação e eventuais erros ou aumento de latência.

## 11.1 Preparar e registrar o estado inicial

Confirme o contexto antes de fazer a alteração:

```bash
kubectl config current-context
kubectl get deployment podinfo -n lab-sre
kubectl get pods -n lab-sre -o wide
kubectl get service,endpointslices -n lab-sre
```

Confirme duas réplicas disponíveis e os endpoints do Service. Se o Deployment não estiver saudável, pare e resolva isso antes do experimento.

Anote o horário de início e escolha um Pod do Deployment pelo nome listado. Em um segundo terminal, inicie tráfego contínuo a partir de `sre-tools`:

```bash
while true; do
  date -Is
  curl -sS -o /dev/null -w 'status=%{http_code} total=%{time_total}s\n' \
    --max-time 5 http://<IP_DE_UM_WORKER>:31198/
  sleep 1
done
```

Deixe o comando ativo durante o teste. Registre erros de conexão, códigos diferentes de 2xx e tempos de resposta. Esse teste simples não representa uma medição estatística de SLO; serve para observar a interrupção durante a recuperação.

## 11.2 Remover um Pod e acompanhar a reconciliação

Em outro terminal, inicie a observação:

```bash
kubectl get pods -n lab-sre -o wide -w
```

Em um terceiro terminal, remova somente um Pod selecionado:

```bash
kubectl delete pod <pod-selecionado> -n lab-sre
```

O controlador deve criar um Pod substituto para voltar ao número desejado de réplicas. Observe a mudança de nome, o estado do Pod novo e em qual nó foi agendado. Interrompa os comandos de observação com `Ctrl+C` após o novo Pod ficar `Ready` e o conjunto estabilizar.

## 11.3 Verificar e medir

Confira o estado final e os endpoints do Service:

```bash
kubectl get deployment podinfo -n lab-sre
kubectl get pods -n lab-sre -o wide
kubectl get endpointslices -n lab-sre
kubectl get events -n lab-sre --sort-by=.metadata.creationTimestamp
```

Registre:

- horário em que o Pod foi removido;
- horário em que o substituto ficou `Ready`;
- duração aproximada até recuperar duas réplicas disponíveis;
- quantidade de erros HTTP ou de conexão durante a observação;
- maior latência observada e se houve impacto visível;
- nó em que o novo Pod foi executado.

## 11.4 Interpretar o resultado

Explique com suas palavras:

1. Qual controlador percebeu que faltava uma réplica?
2. Por que o Pod substituto tem outro nome?
3. O que determina se o Pod entra nos endpoints do Service?
4. O Service manteve o acesso durante a substituição? Que evidência você observou?
5. Como o resultado poderia mudar se houvesse apenas uma réplica, se readiness falhasse ou se não houvesse capacidade nos workers?

Finalize com um registro curto: hipótese, sequência observada, impacto, evidências e uma melhoria ou próxima pergunta. A exclusão de Pod é uma ação disruptiva, mesmo que o Deployment o recrie; execute apenas no namespace de laboratório.

### Critério de conclusão

- O Deployment voltou a manter duas réplicas disponíveis.
- O novo Pod ficou `Ready` e apareceu como endpoint do Service.
- O impacto observado no tráfego foi registrado, incluindo ausência de erros se esse foi o resultado.
- As respostas às perguntas de interpretação foram anotadas.

Depois deste exercício, a próxima atividade planejada é instrumentar o cluster e a aplicação com a stack de observabilidade descrita na etapa seguinte; então, repita o teste e compare as evidências.
