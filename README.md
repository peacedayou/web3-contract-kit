# Web3 Contract Kit

![CI](https://github.com/peacedayou/web3-contract-kit/actions/workflows/ci.yml/badge.svg)

Contrats Solidity prêts à déployer, testés en profondeur et analysés statiquement, pour les
besoins les plus courants d'un projet Web3 : **répartir des jetons dans le temps**,
**distribuer un airdrop** et **sécuriser une trésorerie**.

*Ready-to-deploy, thoroughly tested Solidity contracts: token vesting, Merkle airdrop and multisig wallet.*

| Contrat | Usage | Points clés |
| --- | --- | --- |
| [`TokenVesting`](src/TokenVesting.sol) | Jetons d'équipe, d'investisseurs ou de conseillers débloqués progressivement | Falaise (cliff) + déblocage linéaire, nombre illimité de bénéficiaires, révocation qui rembourse uniquement la part non acquise, rejet des jetons à frais de transfert |
| [`MerkleAirdrop`](src/MerkleAirdrop.sol) | Distribuer des jetons à des milliers d'adresses pour un coût fixe | Preuves de Merkle compatibles avec `StandardMerkleTree` d'OpenZeppelin, suivi des réclamations par bitmap, date limite et récupération des jetons non réclamés |
| [`SimpleMultisig`](src/SimpleMultisig.sol) | Trésorerie partagée M-sur-N | Soumission, confirmation, révocation, exécution d'appels arbitraires ; le seuil ne change que par un vote des propriétaires |

## Qualité

- **Tests unitaires** de chaque chemin, y compris les cas d'erreur
- **Fuzzing** : 1 000 entrées aléatoires par propriété (l'acquisition ne diminue jamais, une révocation conserve exactement les jetons, une preuve aléatoire est toujours rejetée)
- **Tests d'invariants** : des séquences aléatoires de créations, libérations, révocations et sauts dans le temps vérifient que le contrat de vesting reste **toujours solvable**
- **Analyse statique** Slither à chaque commit
- Erreurs personnalisées, événements pour chaque action, protection contre la réentrance, `SafeERC20`
- Basé sur OpenZeppelin Contracts v5.4

## Démarrage

Prérequis : [Foundry](https://book.getfoundry.sh/getting-started/installation).

```bash
git clone --recurse-submodules https://github.com/peacedayou/web3-contract-kit
cd web3-contract-kit
forge build
forge test
forge coverage
```

Déploiement (exemple sur un réseau de test) :

```bash
TOKEN=0x... OWNER=0x... forge script script/DeployVesting.s.sol \
  --rpc-url $RPC_URL --account deployer --broadcast
```

## Générer un airdrop

Construisez l'arbre avec la bibliothèque JavaScript d'OpenZeppelin, puis déployez `MerkleAirdrop` avec la racine obtenue :

```js
import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
const tree = StandardMerkleTree.of(
  [[0, "0xAlice...", "100000000000000000000"], [1, "0xBob...", "250000000000000000000"]],
  ["uint256", "address", "uint256"]
);
console.log(tree.root);             // racine à passer au constructeur
console.log(tree.getProof(0));      // preuve à fournir à claim()
```

## Services

Besoin d'un déploiement personnalisé, d'un contrat adapté à votre projet ou d'une revue de sécurité ?
Contact : [LinkedIn](https://www.linkedin.com/in/pacome-dayou-0b13a7398).

## Avertissement

Ces contrats n'ont pas fait l'objet d'un audit externe professionnel. Faites-les auditer avant de
sécuriser des montants importants. Pour une grande trésorerie, préférez un portefeuille éprouvé comme Safe.

Licence MIT.
