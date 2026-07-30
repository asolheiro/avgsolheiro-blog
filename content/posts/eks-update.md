# Atualizando clusters EKS

## Pré-atualização

- Instale o utilitário [`eksctl`](https://eksctl.io/) utilizado na atualização dos clusters;
- Obtenha a credencial de acesso para um usuário no IAM da AWS, a credencial possui uma `Access Key` e uma `Secret Key`;
  ```bash
  export AWS_ACCESS_KEY_ID=<access_key>
  export AWS_SECRET_ACCESS_KEY=<secret_access_key>
  export AWS_DEFAULT_REGION=<default_region>
  ```
- Instale o [`Pluto CLI`](https://github.com/FairwindsOps/pluto) para analisar a API do Kubernetes;
  ```bash
  ## Obtém um relatório completo do cluster, incluindo helm charts
  pluto detect-all-in-cluster -o wide 2>/dev/null > pluto-output.txt

  ## Obtém um relatório apenas sobre os helm charts instalados
  pluto detect-helm -o wide 2>/dev/null > pluto-output.txt
  ```
> Obs.: Após a obtenção do relatório, é interessante realizar uma nova verificação nos recursos listados para confirmar que o `kind` utilizado no YAML é o mesmo que está presente na coluna `REPLACEMENT` do relatório. Caso não esteja, será necessária intervenção direta, atualizando o yaml em si ou o helm chart.

- Verifique a versão do EKS (Control Planes) no cluster usando o console da AWS:

> ![AWS EKS console](/static/images/03-01.webp)
>
> ***Figura 01: AWS Console - Destaque para a versão do Kubernetes no Control Plane***

- Verifique quais os `nodes groups` existentes e suas respectivas versões. Caso a versão dos workers seja diferente dos control planes, será necessário atualizá-los para que fiquem em paridade de versões do kubernetes antes de prosseguir com a atualização de fato.

> Obs.: É possível que a versão do kubernetes sendo executada nos nodes control plane/API server seja diferente da versão sendo executada nos workers/nodegroups. Esse conceito é chamado de "version skew"

> ![AWS EKS console](/static/images/03-02.webp)
>
> ***Figura 02: AWS Console - Destaque para a versão dos nodegroups***

## Atualizando a API do Kubernetes

- Execute no terminal

```bash
eksctl upgrade cluster \
  --name <CLUSTER_NAME> \
  --version <AIMED_KUBERNETES_VERSION> \
  --approve
```

## Atualizando os nodegroups

- Execute no terminal:

```bash
eksctl upgrade nodegroup <NODEGROUP_NAME> \
  --cluster <CLUSTER_NAME> \
  --kubernetes-version <AIMED_KUBERNETES_VERSION>
```

- Execute o comando acima uma vez para cada nodegroup e versão que se deseja atualizar. Ex.: 4 nodegroups e atualização de 1.25 -> 1.27 demandará oito execuções do comando.

> Obs.: Caso a versão do node group esteja mais de uma versão atrás da versão do kubernetes (Ex.: Kubernetes na 1.27 e NodeGroup na 1.25), é necessário atualizar os node groups primeiro e em seguida a API.
>
> Fluxo correto: 1.25 -> 1.26 -> 1.27b
> Fluxo incorreto: 1.25 -> 1.27
>
> O mesmo vale para atualizações da versão do kubernetes API

- Acompanhe a atualização por meio dos logs no temrinal e na GUI, se disponível. Durante o processo será possível ver os nodes com a versão antiga caindo e nodes com a versão nova subindo. Após isso, verifique se as aplicaçõesque estavam executando antes do processo subiram corretamente e estão em pleno funcionamento.

## Referências

- [Atualizando clusters EKS e o Rancher](https://bedecked-llama-baf.notion.site/Atualizando-clusters-EKS-e-o-Rancher-0c1cce3687cc479eb525301d93957261)
- [Atualizando clusters EKS SIBBR HML](https://bedecked-llama-baf.notion.site/Atualizando-cluster-EKS-SIBBR-HML-1c2f7a634f7f4efca5c9491a9f26e5d8)
