#!/usr/bin/env python3
"""Génère Semainier/Resources/ciqual.json, la bibliothèque d'aliments bruts tirée de la table CIQUAL.

Usage : scripts/ciqual.py

Source : table de composition nutritionnelle Ciqual 2025 (ANSES), licence CC-BY 4.0,
téléchargée depuis Zenodo et gardée en cache dans build/ciqual/.

Le tableau FOODS fait foi : un aliment n'y entre que s'il est vraiment brut et sans inconnue
(ni cuit, ni transformé, ni dépendant de la marque, % de MG précisé), et s'il a sa place dans un
comptage de calories (pas d'herbes, d'épices ni de sel). Quand des variétés ne changent presque
rien (pommes, salades, huiles), on n'en garde qu'une, avec les autres noms dans `aliases`.
Une fusion reprend les valeurs du code choisi, jamais une moyenne.

Chaque ligne garde le nom CIQUAL d'origine : si une nouvelle version de la table réattribue
un code ou renomme l'aliment, le script s'arrête plutôt que d'importer une valeur fausse.
"""
from __future__ import annotations

import json
import sys
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "build" / "ciqual"
OUTPUT = ROOT / "Semainier" / "Resources" / "ciqual.json"

ZENODO = "https://zenodo.org/api/records/17550133/files/{}/content"
FILES = {"foods": "alim_2025_11_03.xml", "contents": "compo_2025_11_03.xml"}
VERSION = "Ciqual 2025 (2025-11-03)"
SOURCE = "Anses. 2025. Table de composition nutritionnelle des aliments Ciqual"

# Constituants CIQUAL : énergie UE 1169/2011 (kcal), protéines (N × Jones), glucides, lipides.
COMPONENTS = {"328": "kcal", "25000": "p", "31000": "c", "40000": "f"}

# Valeurs brutes de `Aisle` (Core/Nutrition.swift).
AISLES = {
    "produce": "Fruits & légumes",
    "meat": "Viandes & poissons",
    "dairy": "Crèmerie & œufs",
    "grocery": "Épicerie",
}

# (code CIQUAL, nom CIQUAL d'origine, nom affiché, mots de recherche en plus, rayon)
FOODS = [
    # fruits
    (13000, 'Abricot, dénoyauté, cru', 'Abricot', '', 'produce'),
    (13001, 'Abricot, dénoyauté, sec', 'Abricot sec', '', 'grocery'),
    (13002, 'Ananas, chair sans peau, cru', 'Ananas', '', 'produce'),
    (13183, 'Baie de goji, séchée', 'Baie de goji séchée', '', 'grocery'),
    (13005, 'Banane, chair sans peau, crue', 'Banane', '', 'produce'),
    (13007, 'Cassis, cru', 'Cassis', '', 'produce'),
    (13008, 'Ceriser, chair et peau, sans noyau, crue', 'Cerise', '', 'produce'),
    (13009, 'Citron, chair sans peau, sans pépins, cru', 'Citron', '', 'produce'),
    (13067, 'Citron vert ou lime, chair sans peau, sans pépins, cru', 'Citron vert', 'lime', 'produce'),
    (13024, 'Clémentine ou mandarine, chair sans peau, sans pépins, crue', 'Clémentine', 'mandarine', 'produce'),
    (13011, 'Datte, chair et peau, sans noyau, sèche', 'Datte sèche', '', 'grocery'),
    (13012, 'Figue, crue', 'Figue', '', 'produce'),
    (13013, 'Figue, sèche', 'Figue sèche', '', 'grocery'),
    (13014, 'Fraise, crue', 'Fraise', '', 'produce'),
    (13015, 'Framboise, crue', 'Framboise', '', 'produce'),
    (13016, 'Fruit de la passion ou maracudja, chair sans peau, avec pépins, cru', 'Fruit de la passion', 'maracuja', 'produce'),
    (13018, 'Grenade, chair sans peau, avec pépins, crue', 'Grenade', '', 'produce'),
    (13019, 'Groseille, crue', 'Groseille', '', 'produce'),
    (13066, 'Kaki, chair et peau, cru', 'Kaki', '', 'produce'),
    (13021, 'Kiwi, chair sans peau, avec pépins, cru', 'Kiwi', '', 'produce'),
    (13023, 'Litchi, chair sans peau, sans noyau, cru', 'Litchi', '', 'produce'),
    (13025, 'Mangue, chair sans peau, sans noyau, crue', 'Mangue', '', 'produce'),
    (13026, 'Melon cantaloup (par ex.: Charentais), chair sans peau, sans pépins, cru', 'Melon', 'charentais cantaloup', 'produce'),
    (13028, 'Myrtille, crue', 'Myrtille', '', 'produce'),
    (13029, 'Mûre (de ronce), crue', 'Mûre', '', 'produce'),
    (13148, 'Nectarine ou brugnon, jaune, chair et peau, sans noyau, crue', 'Nectarine', 'brugnon', 'produce'),
    (13034, 'Orange, chair sans peau, sans pépins, crue', 'Orange', '', 'produce'),
    (13035, 'Papaye, chair sans peau, crue', 'Papaye', '', 'produce'),
    (13036, 'Pastèque, chair sans peau, sans pépins, crue', 'Pastèque', '', 'produce'),
    (13037, 'Poire, chair et peau, crue', 'Poire', '', 'produce'),
    (13040, 'Pomelo (dit Pamplemousse), chair sans peau, sans pépins, cru', 'Pamplemousse', 'pomelo', 'produce'),
    (13039, 'Pomme, chair et peau, crue', 'Pomme', '', 'produce'),
    (13100, 'Prune, sans noyau, crue', 'Prune', '', 'produce'),
    (13027, 'Prune mirabelle, sans noyau, crue', 'Mirabelle', 'prune', 'produce'),
    (13041, 'Prune Reine-Claude, sans noyau, crue', 'Reine-claude', 'prune', 'produce'),
    (13042, 'Pruneau, sans noyau, sec', 'Pruneau', '', 'grocery'),
    (13193, 'Pêche blanche, chair et peau, sans noyau, crue', 'Pêche', '', 'produce'),
    (13101, 'Raisin Chasselas, cru', 'Raisin', 'chasselas', 'produce'),
    (13046, 'Raisin sec', 'Raisin sec', '', 'grocery'),
    (13047, 'Rhubarbe, tige, crue', 'Rhubarbe', '', 'produce'),
    # légumes
    (20052, 'Artichaut, cru', 'Artichaut', '', 'produce'),
    (20282, 'Asperge, blanche ou violette, pelée, crue', 'Asperge', '', 'produce'),
    (20053, 'Aubergine, crue', 'Aubergine', '', 'produce'),
    (13004, 'Avocat, chair sans peau, sans noyau, cru', 'Avocat', '', 'produce'),
    (53100, 'Banane plantain, crue', 'Banane plantain', '', 'produce'),
    (20004, 'Bette ou blette, côte (sans feuille), crue', 'Blette', 'bette', 'produce'),
    (20091, 'Betterave rouge, crue', 'Betterave', '', 'produce'),
    (20057, 'Brocoli, cru', 'Brocoli', '', 'produce'),
    (20009, 'Carotte, crue', 'Carotte', '', 'produce'),
    (20056, 'Champignon de Paris ou champignon de couche, cru', 'Champignon de Paris', '', 'produce'),
    (20103, 'Champignon, chanterelle ou girolle, crue', 'Girolle', 'champignon chanterelle', 'produce'),
    (20160, 'Champignon, cèpe, cru', 'Cèpe', 'champignon', 'produce'),
    (20105, 'Champignon, morille, crue', 'Morille', 'champignon', 'produce'),
    (20114, 'Champignon, pleurote, crue', 'Pleurote', 'champignon', 'produce'),
    (20162, 'Chicorée rouge, crue', 'Chicorée rouge', 'trévise radicchio', 'produce'),
    (20116, 'Chou blanc, cru', 'Chou blanc', '', 'produce'),
    (20340, 'Chou chinois pak choï ou pak choy (feuilles vertes ressemblant à des blettes), cru', 'Pak choï', 'chou chinois', 'produce'),
    (20058, 'Chou de Bruxelles, cru', 'Chou de Bruxelles', '', 'produce'),
    (20218, 'Chou frisé, cru', 'Chou frisé', '', 'produce'),
    (20346, 'Chou kale, cru', 'Chou kale', '', 'produce'),
    (20280, 'Chou romanesco ou brocoli à pomme, cru', 'Chou romanesco', '', 'produce'),
    (20014, 'Chou rouge, cru', 'Chou rouge', '', 'produce'),
    (20069, 'Chou vert, cru', 'Chou vert', '', 'produce'),
    (20016, 'Chou-fleur, cru', 'Chou-fleur', '', 'produce'),
    (20065, 'Chou-rave, cru', 'Chou-rave', '', 'produce'),
    (20019, 'Concombre, chair et peau, cru', 'Concombre', '', 'produce'),
    (20138, 'Courge butternut (doubeurre), chair sans peau, crue', 'Courge butternut', 'doubeurre', 'produce'),
    (20128, 'Courge musquée, chair sans peau, crue', 'Courge musquée', '', 'produce'),
    (20145, 'Courge spaghetti, chair sans peau, crue', 'Courge spaghetti', '', 'produce'),
    (20020, 'Courgette, chair et peau, crue', 'Courgette', '', 'produce'),
    (20022, 'Cresson de fontaine, cru', 'Cresson', '', 'produce'),
    (20023, 'Céleri branche, cru', 'Céleri branche', '', 'produce'),
    (20055, 'Céleri-rave, cru', 'Céleri-rave', '', 'produce'),
    (20026, 'Endive, crue', 'Endive', '', 'produce'),
    (20028, 'Fenouil, cru', 'Fenouil', '', 'produce'),
    (20183, 'Graine germée de haricot mungo ou pousse de "soja", crue', 'Pousses de soja', 'haricot mungo germé', 'produce'),
    (20195, 'Haricot beurre, cru', 'Haricot beurre', '', 'produce'),
    (20061, 'Haricot vert, cru', 'Haricot vert', '', 'produce'),
    (20099, 'Mâche, crue', 'Mâche', '', 'produce'),
    (20064, 'Navet, pelé, cru', 'Navet', '', 'produce'),
    (20239, 'Oignon jaune, cru', 'Oignon', '', 'produce'),
    (20181, 'Panais, cru', 'Panais', '', 'produce'),
    (20072, 'Petits pois, crus', 'Petits pois', '', 'produce'),
    (20151, 'Piment, cru', 'Piment', '', 'produce'),
    (20039, 'Poireau, cru', 'Poireau', '', 'produce'),
    (20173, 'Pois mange-tout ou pois gourmand, cru', 'Pois gourmand', 'mange-tout', 'produce'),
    (20168, 'Poivron jaune, cru', 'Poivron jaune', '', 'produce'),
    (20087, 'Poivron rouge, cru', 'Poivron rouge', '', 'produce'),
    (20085, 'Poivron vert, cru', 'Poivron vert', '', 'produce'),
    (20044, 'Potiron, cru', 'Potiron', 'citrouille', 'produce'),
    (20089, 'Radis noir, cru', 'Radis noir', '', 'produce'),
    (20045, 'Radis rouge, cru', 'Radis', '', 'produce'),
    (20217, 'Roquette, crue', 'Roquette', '', 'produce'),
    (20201, 'Rutabaga, cru', 'Rutabaga', '', 'produce'),
    (25604, 'Salade verte, crue, sans assaisonnement', 'Salade verte', 'laitue batavia romaine iceberg sucrine feuille de chêne frisée scarole', 'produce'),
    (20172, 'Tomate cerise, crue', 'Tomate cerise', '', 'produce'),
    (20276, 'Tomate ronde, crue', 'Tomate', '', 'produce'),
    (20097, 'Échalote, crue', 'Échalote', '', 'produce'),
    (20059, 'Épinard, cru', 'Épinard', '', 'produce'),
    # herbes
    (11000, 'Ail, cru', 'Ail', '', 'produce'),
    # épices
    (11074, 'Gingembre, racine fraîche', 'Gingembre frais', '', 'produce'),
    # pommes de terre et autres tubercules
    (53502, 'Igname, pelée, crue', 'Igname', '', 'produce'),
    (54031, 'Manioc, racine crue', 'Manioc', '', 'produce'),
    (4101, 'Patate douce, crue', 'Patate douce', '', 'produce'),
    (4008, 'Pomme de terre, sans peau, crue', 'Pomme de terre', '', 'produce'),
    (4000, 'Tapioca ou perles du Japon, cru', 'Tapioca', 'perles du Japon', 'grocery'),
    (20196, 'Topinambour, cru', 'Topinambour', '', 'produce'),
    # légumineuses
    (20517, 'Fève à écosser, fraîche, crue', 'Fève fraîche', '', 'produce'),
    (20518, 'Fève, sèche', 'Fève sèche', '', 'grocery'),
    (20501, 'Haricot blanc, sec', 'Haricot blanc sec', 'lingot coco', 'grocery'),
    (20539, 'Haricot flageolet, vert, sec', 'Flageolet sec', 'haricot', 'grocery'),
    (20530, 'Haricot mungo, sec', 'Haricot mungo sec', '', 'grocery'),
    (20525, 'Haricot rouge, sec', 'Haricot rouge sec', '', 'grocery'),
    (20585, 'Lentille verte, sèche', 'Lentilles sèches', 'verte corail blonde', 'grocery'),
    (20515, 'Pois cassé, sec', 'Pois cassés secs', '', 'grocery'),
    (20516, 'Pois chiche, sec', 'Pois chiches secs', '', 'grocery'),
    # pâtes, riz et céréales
    (9310, 'Avoine, crue', 'Avoine crue', "flocons d'avoine", 'grocery'),
    (9003, 'Blé de Khorasan, cru', 'Blé Khorasan cru', 'kamut', 'grocery'),
    (9690, 'Boulgour de blé, cru', 'Boulgour cru', '', 'grocery'),
    (9321, 'Orge perlée, crue', 'Orge perlée crue', '', 'grocery'),
    (9810, 'Pâtes sèches, standard, crues', 'Pâtes sèches crues', 'spaghetti penne coquillettes', 'grocery'),
    (9870, 'Pâtes sèches, au blé complet, crues', 'Pâtes complètes crues', '', 'grocery'),
    (9821, 'Pâtes sèches, aux oeufs, crues', 'Pâtes aux œufs sèches crues', '', 'grocery'),
    (9815, 'Pâtes fraîches, aux oeufs, crues', 'Pâtes fraîches aux œufs crues', '', 'grocery'),
    (9863, 'Pâtes ou nouilles asiatiques sèches, au blé et aux oeufs, nature, crues', 'Nouilles aux œufs sèches crues', 'asiatiques', 'grocery'),
    (9340, 'Quinoa, cru', 'Quinoa cru', '', 'grocery'),
    (9100, 'Riz blanc, cru', 'Riz blanc cru', 'basmati thaï', 'grocery'),
    (9102, 'Riz complet, cru', 'Riz complet cru', '', 'grocery'),
    (9109, 'Riz rouge, cru', 'Riz rouge cru', '', 'grocery'),
    (9108, 'Riz sauvage, cru', 'Riz sauvage cru', '', 'grocery'),
    (9380, 'Sarrasin complet, cru', 'Sarrasin cru', 'kasha', 'grocery'),
    (9900, 'Vermicelles de riz sèches, crues', 'Vermicelles de riz crues', '', 'grocery'),
    (9902, 'Vermicelles de soja sèches, crues', 'Vermicelles de soja crues', '', 'grocery'),
    (9001, 'Épeautre, cru', 'Épeautre cru', '', 'grocery'),
    # farines
    (9510, 'Amidon de maïs ou fécule de maïs', 'Fécule de maïs', 'amidon maïzena', 'grocery'),
    (9436, 'Farine de blé tendre ou froment T55 (pour pains)', 'Farine de blé T55', 'blanche T45 T65', 'grocery'),
    (9445, 'Farine de blé tendre ou froment T80', 'Farine de blé T80', 'semi-complète', 'grocery'),
    (9415, 'Farine de blé tendre ou froment T150', 'Farine de blé T150', 'complète T110', 'grocery'),
    (9480, "Farine d'épeautre (grand épeautre)", "Farine d'épeautre", '', 'grocery'),
    (9570, 'Farine de châtaigne', 'Farine de châtaigne', '', 'grocery'),
    (9545, 'Farine de maïs', 'Farine de maïs', '', 'grocery'),
    (9580, 'Farine de pois chiche', 'Farine de pois chiche', '', 'grocery'),
    (9520, 'Farine de riz', 'Farine de riz', '', 'grocery'),
    (9540, 'Farine de sarrasin', 'Farine de sarrasin', 'blé noir', 'grocery'),
    (9533, 'Farine de seigle T130', 'Farine de seigle', '', 'grocery'),
    (9550, "Farine d'orge", "Farine d'orge", '', 'grocery'),
    # fruits à coque et graines oléagineuses
    (15000, 'Amande, avec peau, sans sel ajouté', 'Amande', 'émondée', 'grocery'),
    (15001, 'Cacahuète, sans sel ajouté', 'Cacahuète', 'arachide', 'grocery'),
    (15047, 'Chia, graine, séchée', 'Graines de chia', '', 'grocery'),
    (15024, 'Châtaigne, crue', 'Châtaigne', 'marron', 'grocery'),
    (15064, 'Courge, graine, séchée', 'Graines de courge', '', 'grocery'),
    (15052, 'Lin, brun, graine', 'Graines de lin', '', 'grocery'),
    (15004, 'Noisette, sans sel ajouté', 'Noisette', '', 'grocery'),
    (15006, 'Noix de coco, chair, fraîche', 'Noix de coco fraîche', '', 'grocery'),
    (15007, 'Noix de coco, chair, sèche', 'Noix de coco râpée', 'sèche', 'grocery'),
    (15027, 'Noix de macadamia, sans sel ajouté', 'Noix de macadamia', '', 'grocery'),
    (15026, 'Noix de pécan, sans sel ajouté', 'Noix de pécan', '', 'grocery'),
    (15008, "Noix du Brésil ou noix d'Amazonie, sans sel ajouté", 'Noix du Brésil', '', 'grocery'),
    (15005, 'Noix, cerneau, séchée', 'Noix', 'cerneaux', 'grocery'),
    (15025, 'Pignon de pin', 'Pignons de pin', '', 'grocery'),
    (15010, 'Sésame, graine', 'Sésame', '', 'grocery'),
    (15011, 'Tournesol, graine', 'Graines de tournesol', '', 'grocery'),
    # huiles et graisses végétales
    (17270, "Huile d'olive vierge extra", 'Huile', 'olive colza tournesol arachide noix sésame lin pépins de raisin soja maïs avocat noisette coco', 'grocery'),
    # beurres
    (16400, 'Beurre à 80% MG minimum, doux', 'Beurre doux', '', 'dairy'),
    (16402, 'Beurre à 80% MG, demi-sel', 'Beurre demi-sel', 'salé', 'dairy'),
    (16410, 'Beurre à 60-62% MG, à teneur réduite en matière grasse, doux', 'Beurre allégé 60 %', '', 'dairy'),
    (16415, 'Beurre à 39-41% MG, léger, doux', 'Beurre allégé 40 %', '', 'dairy'),
    (16401, 'Huile de beurre ou beurre concentré', 'Beurre clarifié', 'ghee', 'dairy'),
    # laits
    (19023, 'Lait entier, UHT', 'Lait entier', '', 'dairy'),
    (19041, 'Lait demi-écrémé, UHT', 'Lait demi-écrémé', '', 'dairy'),
    (19050, 'Lait écrémé, UHT', 'Lait écrémé', '', 'dairy'),
    (19060, 'Lait demi-écrémé (ou à teneur en matière grasse légèrement inférieure), UHT,  à teneur réduite en lactose', 'Lait demi-écrémé sans lactose', '', 'dairy'),
    (19200, 'Lait de chèvre, entier, UHT', 'Lait de chèvre entier', '', 'dairy'),
    (19201, 'Lait de chèvre, demi-écrémé, UHT', 'Lait de chèvre demi-écrémé', '', 'dairy'),
    (19250, 'Lait de brebis, entier', 'Lait de brebis', '', 'dairy'),
    # crèmes et spécialités à base de crème
    (19417, 'Crème 30% MG, fluide, UHT', 'Crème 30 % MG', 'fraîche fluide épaisse liquide', 'dairy'),
    # produits laitiers frais et alternatives végétales
    (19644, 'Fromage blanc, nature, 0% MG', 'Fromage blanc 0 %', '', 'dairy'),
    (19646, 'Fromage blanc, nature, 2-3% MG', 'Fromage blanc 3 %', '', 'dairy'),
    (19711, 'Fromage blanc, nature, 7-8% MG', 'Fromage blanc 8 %', '', 'dairy'),
    (19639, 'Faisselle, 0% MG', 'Faisselle 0 %', '', 'dairy'),
    (19641, 'Faisselle, 6% MG environ', 'Faisselle 6 %', '', 'dairy'),
    (19663, 'Fromage frais type petit suisse, nature, 0% MG', 'Petit-suisse 0 %', '', 'dairy'),
    (19664, 'Fromage frais type petit suisse, nature, 4% MG environ', 'Petit-suisse 4 %', '', 'dairy'),
    (19666, 'Fromage frais type petit suisse, nature, 10% MG environ', 'Petit-suisse 10 %', '', 'dairy'),
    (19594, 'Yaourt ou lait fermenté, nature, 0% MG', 'Yaourt nature 0 %', '', 'dairy'),
    (19554, 'Yaourt au lait de brebis, nature, 3% MG environ', 'Yaourt de brebis 3 %', '', 'dairy'),
    (19882, 'Yaourt au lait de brebis, nature, 6% MG environ', 'Yaourt de brebis 6 %', '', 'dairy'),
    # oeufs
    (22000, 'Oeuf cru', 'Œuf', '', 'dairy'),
    (22001, "Oeuf, blanc (blanc d'oeuf), cru", "Blanc d'œuf", '', 'dairy'),
    (22002, "Oeuf, jaune (jaune d'oeuf), cru", "Jaune d'œuf", '', 'dairy'),
    # sucres, miels et assimilés
    (31008, 'Miel', 'Miel', '', 'grocery'),
    (31034, "Sirop d'érable", "Sirop d'érable", '', 'grocery'),
    (31016, 'Sucre blanc', 'Sucre blanc', '', 'grocery'),
    (31017, 'Sucre roux', 'Sucre roux', 'cassonade', 'grocery'),
    # viandes crues
    (21514, 'Agneau, collier cru', 'Agneau, collier cru', '', 'meat'),
    (21525, 'Agneau, côte découverte crue', 'Agneau, côte découverte crue', '', 'meat'),
    (21516, 'Agneau, côte filet crue', 'Agneau, côte filet crue', '', 'meat'),
    (21517, 'Agneau, côte première crue', 'Agneau, côte première crue', '', 'meat'),
    (21502, 'Agneau, gigot cru', 'Agneau, gigot cru', '', 'meat'),
    (21515, 'Agneau, selle crue', 'Agneau, selle crue', '', 'meat'),
    (21504, 'Agneau, épaule crue', 'Agneau, épaule crue', '', 'meat'),
    (6003, 'Boeuf, basse-côte crue', 'Bœuf, basse-côte crue', '', 'meat'),
    (6212, "Boeuf, bavette d'aloyau crue", 'Bœuf, bavette crue', '', 'meat'),
    (6202, 'Boeuf, boule de macreuse crue', 'Bœuf, macreuse crue', '', 'meat'),
    (6240, 'Boeuf, collier cru', 'Bœuf, collier cru', '', 'meat'),
    (6001, 'Boeuf, côte crue', 'Bœuf, côte crue', '', 'meat'),
    (6103, 'Boeuf, entrecôte crue', 'Bœuf, entrecôte crue', '', 'meat'),
    (6111, 'Boeuf, faux-filet cru', 'Bœuf, faux-filet cru', '', 'meat'),
    (6116, 'Boeuf, filet cru', 'Bœuf, filet cru', '', 'meat'),
    (6102, 'Boeuf, gîte à la noix cru', 'Bœuf, gîte à la noix cru', '', 'meat'),
    (6130, 'Boeuf, hampe crue', 'Bœuf, hampe crue', '', 'meat'),
    (6140, 'Boeuf, joue crue', 'Bœuf, joue crue', '', 'meat'),
    (6204, 'Boeuf, onglet cru', 'Bœuf, onglet cru', '', 'meat'),
    (6270, 'Boeuf, paleron cru', 'Bœuf, paleron cru', '', 'meat'),
    (6122, 'Boeuf, plat de côtes cru', 'Bœuf, plat de côtes cru', '', 'meat'),
    (6311, 'Boeuf, queue crue', 'Bœuf, queue crue', '', 'meat'),
    (6106, 'Boeuf, rond de gîte cru', 'Bœuf, rond de gîte cru', '', 'meat'),
    (6206, 'Boeuf, rumsteck cru', 'Bœuf, rumsteck cru', '', 'meat'),
    (6160, 'Boeuf, tende de tranche crue', 'Bœuf, tende de tranche crue', '', 'meat'),
    (6002, 'Boeuf, épaule crue', 'Bœuf, épaule crue', '', 'meat'),
    (6250, 'Boeuf, steak haché 5% MG cru', 'Bœuf, steak haché 5 % cru', '', 'meat'),
    (6252, 'Boeuf, steak haché 10% MG cru', 'Bœuf, steak haché 10 % cru', '', 'meat'),
    (6254, 'Boeuf, steak haché 15% MG cru', 'Bœuf, steak haché 15 % cru', '', 'meat'),
    (6256, 'Boeuf, steak haché 20% MG cru', 'Bœuf, steak haché 20 % cru', '', 'meat'),
    (36206, 'Canard, magret cru', 'Canard, magret cru', '', 'meat'),
    (36310, 'Dinde, aile crue', 'Dinde, aile crue', '', 'meat'),
    (36307, 'Dinde, cuisse, viande crue', 'Dinde, cuisse sans peau crue', '', 'meat'),
    (36305, 'Dinde, cuisse, viande et peau crues', 'Dinde, cuisse avec peau crue', '', 'meat'),
    (36304, 'Dinde, escalope crue', 'Dinde, escalope crue', '', 'meat'),
    (34001, 'Lapin, viande crue', 'Lapin cru', '', 'meat'),
    (36703, 'Pintade, cuisse crue', 'Pintade, cuisse crue', '', 'meat'),
    (36702, 'Pintade, poitrine crue', 'Pintade, filet cru', 'poitrine', 'meat'),
    (36023, 'Poulet, aile, viande et peau crues', 'Poulet, aile crue', '', 'meat'),
    (36024, 'Poulet, cuisse, viande crue', 'Poulet, cuisse sans peau crue', '', 'meat'),
    (36002, 'Poulet, cuisse, viande et peau crue', 'Poulet, cuisse avec peau crue', '', 'meat'),
    (36037, 'Poulet, cuisse, viande et peau crues bio', 'Poulet bio, cuisse avec peau crue', '', 'meat'),
    (36038, 'Poulet, cuisse, viande et peau crues label rouge', 'Poulet label rouge, cuisse avec peau crue', '', 'meat'),
    (36017, 'Poulet, filet sans peau cru', 'Poulet, filet cru', 'blanc escalope', 'meat'),
    (36039, 'Poulet, filet sans peau cru, bio', 'Poulet bio, filet cru', 'blanc', 'meat'),
    (36040, 'Poulet, filet sans peau cru, label rouge', 'Poulet label rouge, filet cru', 'blanc', 'meat'),
    (36019, 'Poulet, haut de cuisse, viande crue', 'Poulet, haut de cuisse sans peau cru', '', 'meat'),
    (36022, 'Poulet, pilon cru', 'Poulet, pilon cru', '', 'meat'),
    (36029, 'Poulet, poitrine, viande et peau crues', 'Poulet, blanc avec peau cru', 'poitrine', 'meat'),
    (28104, 'Porc, carré cru', 'Porc, carré cru', '', 'meat'),
    (28100, 'Porc, côte crue', 'Porc, côte crue', '', 'meat'),
    (28460, 'Porc, escalope de jambon crue', 'Porc, escalope crue', '', 'meat'),
    (28204, 'Porc, filet mignon cru', 'Porc, filet mignon cru', '', 'meat'),
    (28473, 'Porc, jambon sans jarret, sans bateau, découenné, dégraissé, désossé, cru', 'Porc, jambon cru (rôti)', 'noix', 'meat'),
    (28474, 'Porc, jambonneau arrière, découenné, dégraisssé, désossé, cru', 'Porc, jambonneau cru', '', 'meat'),
    (28475, 'Porc, maigre 90/10 cru', 'Porc, haché 10 % cru', 'maigre 90/10', 'meat'),
    (28476, 'Porc, maigre 80/20 cru', 'Porc, haché 20 % cru', 'maigre 80/20', 'meat'),
    (28009, 'Porc, palette crue', 'Porc, palette crue', '', 'meat'),
    (28002, 'Porc, poitrine crue', 'Porc, poitrine crue', '', 'meat'),
    (28102, 'Porc, rouelle de jambon crue', 'Porc, rouelle crue', '', 'meat'),
    (28400, 'Porc, travers cru', 'Porc, travers cru', '', 'meat'),
    (28302, 'Porc, échine crue', 'Porc, échine crue', '', 'meat'),
    (28001, 'Porc, épaule crue', 'Porc, épaule crue', '', 'meat'),
    (6513, 'Veau, carré cru', 'Veau, carré cru', '', 'meat'),
    (6590, 'Veau, collier cru', 'Veau, collier cru', '', 'meat'),
    (6510, 'Veau, côte crue', 'Veau, côte crue', '', 'meat'),
    (6521, 'Veau, escalope crue', 'Veau, escalope crue', '', 'meat'),
    (6530, 'Veau, filet cru', 'Veau, filet cru', '', 'meat'),
    (6583, 'Veau, jarret cru', 'Veau, jarret cru', 'osso-buco', 'meat'),
    (6522, 'Veau, noix,crue', 'Veau, noix crue', '', 'meat'),
    (6540, 'Veau, poitrine crue', 'Veau, poitrine crue', 'tendron', 'meat'),
    (6536, 'Veau, steak haché 15% MG cru', 'Veau, haché 15 % cru', '', 'meat'),
    (6535, 'Veau, steak haché 20% MG cru', 'Veau, haché 20 % cru', '', 'meat'),
    (6560, 'Veau, épaule crue', 'Veau, épaule crue', '', 'meat'),
    # poissons crus
    (26079, 'Anchois, cru', 'Anchois cru', '', 'meat'),
    (26205, 'Bar commun ou loup (Méditerranée), sauvage, cru', 'Bar sauvage cru', 'loup', 'meat'),
    (26206, 'Bar commun ou loup (Méditerranée), élevage, cru', "Bar d'élevage cru", 'loup', 'meat'),
    (26208, 'Baudroie rousse ou Lotte, crue', 'Lotte crue', 'baudroie', 'meat'),
    (27011, 'Brochet, cru', 'Brochet cru', '', 'meat'),
    (26043, 'Cabillaud, cru', 'Cabillaud cru', 'morue dos', 'meat'),
    (26055, 'Carrelet ou plie ou plie commune, cru', 'Carrelet cru', 'plie', 'meat'),
    (26099, 'Dorade grise ou daurade grise, ou griset, crue', 'Daurade grise crue', 'dorade griset', 'meat'),
    (26080, 'Dorade royale ou daurade ou vraie daurade, sauvage, crue', 'Daurade royale sauvage crue', 'dorade', 'meat'),
    (26088, 'Dorade royale ou daurade ou vraie daurade, élevage, crue', "Daurade royale d'élevage crue", 'dorade', 'meat'),
    (26082, 'Espadon, cru', 'Espadon cru', '', 'meat'),
    (26009, "Flétan de l'Atlantique ou flétan, cru", 'Flétan cru', '', 'meat'),
    (26238, 'Hareng gras, cru', 'Hareng gras cru', '', 'meat'),
    (26237, 'Hareng maigre, cru', 'Hareng maigre cru', '', 'meat'),
    (26129, 'Lieu jaune ou colin, cru', 'Lieu jaune cru', 'colin', 'meat'),
    (26134, 'Lieu noir, cru', 'Lieu noir cru', 'colin', 'meat'),
    (26006, "Lieu ou colin d'Alaska, cru", "Colin d'Alaska cru", 'lieu', 'meat'),
    (26057, 'Limande, crue', 'Limande crue', '', 'meat'),
    (26135, 'Limande-sole, crue', 'Limande-sole crue', '', 'meat'),
    (26051, 'Maquereau, cru', 'Maquereau cru', '', 'meat'),
    (26095, 'Merlan, cru', 'Merlan cru', '', 'meat'),
    (26044, 'Merlu, cru', 'Merlu cru', 'colin', 'meat'),
    (27017, 'Pangas, poisson-chat, machoiron, cru', 'Pangasius cru', 'panga', 'meat'),
    (27025, 'Perche du Nil, crue', 'Perche du Nil crue', '', 'meat'),
    (26052, 'Raie, crue', 'Raie crue', '', 'meat'),
    (26085, 'Rouget-barbet de roche, cru', 'Rouget cru', 'barbet', 'meat'),
    (26074, 'Roussette ou petite roussette ou saumonette, crue', 'Saumonette crue', 'roussette', 'meat'),
    (26104, 'Saint-Pierre, cru', 'Saint-Pierre cru', '', 'meat'),
    (27024, 'Sandre, cru', 'Sandre cru', '', 'meat'),
    (26065, 'Sardine, crue', 'Sardine crue', '', 'meat'),
    (26161, 'Saumon, sauvage, cru', 'Saumon sauvage cru', '', 'meat'),
    (26036, 'Saumon, élevage, cru', "Saumon d'élevage cru", '', 'meat'),
    (26058, 'Sole, crue', 'Sole crue', '', 'meat'),
    (26064, 'Thon albacore, cru', 'Thon albacore cru', '', 'meat'),
    (26076, 'Thon germon ou thon blanc, cru', 'Thon blanc cru', 'germon', 'meat'),
    (26069, 'Thon rouge, cru', 'Thon rouge cru', '', 'meat'),
    (27019, 'Tilapia, cru', 'Tilapia cru', '', 'meat'),
    (27009, 'Truite arc en ciel, élevage, crue', 'Truite arc-en-ciel crue', '', 'meat'),
    (27008, 'Truite ou truite fario, élevage, crue', 'Truite fario crue', '', 'meat'),
    (27021, 'Truite saumonée, crue', 'Truite saumonée crue', '', 'meat'),
    (26042, 'Turbot, sauvage, cru', 'Turbot sauvage cru', '', 'meat'),
    (26201, 'Turbot, élevage, cru', "Turbot d'élevage cru", '', 'meat'),
    (26122, 'Églefin, cru', 'Églefin cru', 'haddock', 'meat'),
    # mollusques et crustacés crus
    (10001, 'Calmar ou calamar ou encornet, cru', 'Calamar cru', 'encornet calmar', 'meat'),
    (10017, 'Clam, praire ou palourde, cru', 'Palourde crue', 'clam praire', 'meat'),
    (10045, 'Coquille Saint-Jacques, noix, crue', 'Saint-Jacques crue', 'noix coquille', 'meat'),
    (10039, 'Crabe, cru', 'Crabe cru', '', 'meat'),
    (10021, 'Crevette, crue', 'Crevette crue', 'gambas', 'meat'),
    (10010, 'Homard, cru', 'Homard cru', '', 'meat'),
    (10035, 'Huître creuse, crue', 'Huître creuse', '', 'meat'),
    (10036, 'Huître plate, crue', 'Huître plate', '', 'meat'),
    (10015, 'Langouste, crue', 'Langouste crue', '', 'meat'),
    (10024, 'Langoustine, crue', 'Langoustine crue', '', 'meat'),
    (10014, 'Moule commune, crue', 'Moule crue', '', 'meat'),
    (10018, 'Poulpe, cru', 'Poulpe cru', '', 'meat'),
    (10016, 'Seiche, crue', 'Seiche crue', '', 'meat'),
]


def download(name: str) -> Path:
    path = CACHE / name
    if not path.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        print(f"Téléchargement de {name}…")
        urllib.request.urlretrieve(ZENODO.format(name), path.with_suffix(".part"))
        path.with_suffix(".part").rename(path)
    return path


def text(element, tag: str) -> str:
    return (element.findtext(tag) or "").strip()


def number(raw: str) -> float | None:
    """Teneur CIQUAL : « 12,3 », « traces » et « < 0,5 » (comptés 0), « - » (inconnue)."""
    if raw in ("", "-"):
        return None
    if raw == "traces" or raw.startswith("<"):
        return 0.0
    return float(raw.replace(",", "."))


def main() -> int:
    codes = {code for code, *_ in FOODS}
    ciqual_names = {
        int(text(a, "alim_code")): text(a, "alim_nom_fr")
        for a in ET.parse(download(FILES["foods"])).getroot()
    }
    contents: dict[int, dict[str, float | None]] = {code: {} for code in codes}
    for _, e in ET.iterparse(download(FILES["contents"])):
        if e.tag == "COMPO":
            code, component = int(text(e, "alim_code")), text(e, "const_code")
            if code in codes and component in COMPONENTS:
                contents[code][COMPONENTS[component]] = number(text(e, "teneur"))
            e.clear()

    errors, foods, seen = [], [], set()
    for code, ciqual_name, name, aliases, aisle in FOODS:
        if name in seen:
            errors.append(f"{code} : nom affiché en double « {name} »")
        seen.add(name)
        if ciqual_names.get(code) != ciqual_name:
            errors.append(f"{code} : attendu « {ciqual_name} », la table dit « {ciqual_names.get(code)} »")
            continue
        t = contents[code]
        if any(t.get(m) is None for m in "pcf"):
            errors.append(f"{code} « {ciqual_name} » : macros incomplètes {t}")
            continue
        # Sans kcal publiées, on les recalcule en 4/4/9, comme l'appli.
        kcal = t.get("kcal")
        if kcal is None:
            kcal = round(t["p"] * 4 + t["c"] * 4 + t["f"] * 9, 1)
        foods.append({
            "code": code, "name": name, "aliases": aliases, "aisle": AISLES[aisle],
            "kcal": kcal, "p": t["p"], "c": t["c"], "f": t["f"],
        })

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    foods.sort(key=lambda a: a["name"])
    lines = ",\n".join("    " + json.dumps(a, ensure_ascii=False) for a in foods)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(
        "{\n"
        f'  "version": {json.dumps(VERSION, ensure_ascii=False)},\n'
        f'  "source": {json.dumps(SOURCE, ensure_ascii=False)},\n'
        f'  "foods": [\n{lines}\n  ]\n'
        "}\n",
        encoding="utf-8",
    )
    print(f"{len(foods)} aliments écrits dans {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
