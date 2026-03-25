# BioPRIO Assessment Instructions (LLM Version)

## Overview

BioPRIO is a risk assessment framework for **terrestrial invertebrates** (invasive arthropods, ecological threat species) adapted from FinnPRIO. The framework evaluates species across four modules:

1. **ENTRY (ENT)** - Probability of entering the risk assessment area
2. **ESTABLISHMENT (EST)** - Probability of establishing and spreading
3. **IMPACT (IMP)** - Economic and environmental consequences
4. **MANAGEMENT (MAN)** - Difficulty of prevention and control

**Risk Assessment Area:** Norway (or specified region)

---

## Output Format

For each question, provide your response in this JSON structure:

```json
{
  "question_id": "ENT1",
  "selected_option": "b",
  "min_option": "a",
  "max_option": "c",
  "confidence": "medium",
  "justification": "Concise explanation citing evidence..."
}
```

- `selected_option`: Most likely answer (letter)
- `min_option`: Lower bound of uncertainty range
- `max_option`: Upper bound of uncertainty range
- `confidence`: "low", "medium", or "high"
- `justification`: 2-4 sentences with citations/evidence

---

## Entry Pathways

Before answering pathway questions (ENT2-4), identify relevant pathways:

| ID | Pathway | Group | Description |
|----|---------|-------|-------------|
| 1 | Contaminant of seeds or growing media | 1 | Hitchhiking in soil, seeds, or planting substrate |
| 2 | Plants for planting | 1 | Potted plants, cuttings, bulbs, rootstocks |
| 3 | Wood and wood packaging | 1 | Timber, pallets, firewood, bark |
| 4 | Agricultural commodities | 1 | Food products, fodder, raw materials |
| 5 | Cut plant material | 1 | Cut flowers, Christmas trees, decorative branches |
| 6 | Hitchhiking | 2 | Vehicles, containers, passengers, non-host cargo |
| 7 | Natural spread | 3 | Active flight, wind dispersal, walking from adjacent areas |
| 8 | Intentional introduction | 3 | Biological control, pet trade, research releases |

**Group affects scoring formula:**
- Group 1: Uses ENT1 × ENT2 × ENT3 × ENT4
- Group 2: Uses ENT1 × ENT2 × ENT4 (no trade volume)
- Group 3: Uses ENT2 × ENT4 only (no distribution or trade)

---

## ENTRY Questions

### ENT1: Global Distribution

**Question:** How wide is the current global geographical distribution of the species?

| Option | Points | Interpretation |
|--------|--------|----------------|
| a. Small | 1 | Limited to one region/continent, localized |
| b. Medium | 2 | Present on 2-3 continents, moderate spread |
| c. Large | 3 | Widespread across multiple continents, cosmopolitan |

**Consider:**
- Native range extent
- Number of continents with established populations
- Compare to reference: circle ~2000 km diameter

**Example justification:**
> "Native to Southeast Asia with established invasive populations in North America (since 2014), Europe (since 2019), and Australia (since 2021). Distribution spans 4 continents, exceeding the reference circle. **Score: c (Large)**"

---

### ENT2A: Transport Likelihood (without measures)

**Question:** Not taking into account current official management measures, can the species be transported to the risk assessment area via the considered pathway?

| Option | Points | Interpretation |
|--------|--------|----------------|
| a. No it cannot | 0 | Biologically impossible or pathway doesn't exist |
| b. Very unlikely | 0.5 | Extremely rare, few historical cases |
| c. Unlikely | 1 | Possible but uncommon |
| d. Likely | 2 | Regular occurrence, documented interceptions |
| e. Very likely | 3 | Highly probable, frequent interceptions |

**Consider:**
- Species association with the commodity/pathway
- Historical interception records (Europhyt, EPPO alerts)
- Survival during transport conditions
- Volume of trade in this pathway

**Example justification:**
> "The species is strongly associated with wood packaging material, with 47 interceptions recorded in Europhyt 2018-2023. It can survive >30 days in untreated wood. **Score: d (Likely)**"

---

### ENT2B: Transport Likelihood (with measures)

**Question:** Taking into account current official management measures, can the species be transported to the risk assessment area via the considered pathway?

Same options as ENT2A. Consider:
- ISPM 15 treatment requirements for wood
- Phytosanitary certificates
- Import prohibitions
- Inspection regimes
- Effectiveness of current measures

**Example justification:**
> "ISPM 15 heat treatment (56°C/30 min) is required for wood packaging from third countries. Studies show 99% mortality, but non-compliance occurs. Post-measure interceptions reduced by ~80%. **Score: c (Unlikely)**"

---

### ENT3: Trade Volume

**Question:** How large a volume of the considered commodities, plant material, or other conveyances potentially associated with the species is traded into the risk assessment area annually?

| Option | Points | Interpretation |
|--------|--------|----------------|
| a. Non-existent | 0 | No trade in this commodity |
| b. Small | 1 | <1000 tonnes/year or <10,000 units |
| c. Medium | 2 | Moderate regular trade |
| d. Large | 3 | Major trade volume, frequent shipments |

**Consider:**
- Import statistics for the commodity
- Source countries where species is present
- Frequency of shipments

**Example justification:**
> "Norway imports ~50,000 tonnes of fresh fruit annually from regions where the species occurs (Spain, Italy, Turkey). Trade is continuous year-round. **Score: d (Large)**"

---

### ENT4: Transfer to Suitable Habitat

**Question:** Can the species transfer to a suitable host, prey organism, or habitat after entering the risk assessment area via the pathway?

| Option | Points | Interpretation |
|--------|--------|----------------|
| a. No it cannot | 0 | No suitable hosts/habitats exist or accessible |
| b. Very unlikely | 0.5 | Hosts distant from entry points, hostile environment |
| c. Unlikely | 1 | Some hosts exist but transfer challenging |
| d. Likely | 2 | Suitable hosts near entry points, transfer feasible |
| e. Very likely | 3 | Hosts widespread, easy transfer from entry pathway |

**Consider:**
- Location of entry points (ports, warehouses, retail)
- Distance to suitable hosts/habitats
- Species mobility and dispersal ability
- Seasonal timing of arrivals vs. host availability

**Example justification:**
> "Wood packaging arrives at construction sites and warehouses, often near forests with suitable conifer hosts. Adults can fly 2-5 km. Summer arrivals coincide with active dispersal period. **Score: d (Likely)**"

---

## ESTABLISHMENT Questions

### EST1: Reproduction and Overwintering

**Question:** Could the species reproduce and overwinter (or persist through unfavourable seasons) in the risk assessment area, taking into account the prevailing climate and land use conditions?

| Option | Points | Interpretation |
|--------|--------|----------------|
| a. No it could not | 0 | Climate unsuitable, cannot complete lifecycle |
| b. Could, but unlikely | 1.5 | Marginal conditions, occasional survival possible |
| c. Could, and likely | 4.5 | Suitable conditions in significant areas |
| d. Could, and very likely | 9 | Highly suitable climate, multiple generations possible |

**Consider:**
- Climate matching (native range vs. risk area)
- Cold hardiness / winter survival
- Degree-day requirements for development
- Availability of overwintering sites
- Indoor vs. outdoor establishment potential

**Example justification:**
> "Native range includes areas with similar climate to southern Norway (Dfb/Cfb Köppen zones). Cold-hardy to -15°C, matching Norwegian winter minima. Completes 1-2 generations/year at Norwegian temperatures. Indoor populations possible year-round. **Score: c (Could, and likely)**"

---

### EST2: Suitable Hosts/Habitats

**Question:** How large an area of suitable hosts, prey organisms, or habitats does the risk assessment area contain?

| Option | Points | Interpretation |
|--------|--------|----------------|
| a. Not at all | 0 | No suitable hosts/habitats exist |
| b. Very small | 1 | <100 ha or very localized |
| c. Small | 2 | 100-1,000 ha |
| d. Medium | 3 | 1,000-10,000 ha |
| e. Large | 4 | >10,000 ha, widespread |

**Consider:**
- For herbivores: host plant distribution and cultivation area
- For predators: prey species abundance and distribution
- For detritivores: suitable substrate availability
- Natural + cultivated/managed habitats

**Example justification:**
> "Primary hosts include Quercus and Castanea species. Norway has ~30,000 ha of oak-dominated forest plus urban plantings. Secondary hosts (Betula, other deciduous) add >500,000 ha. **Score: e (Large)**"

---

### EST3: Spread Rate

**Question:** How quickly would the species likely spread in the risk assessment area?

| Option | Points | Interpretation |
|--------|--------|----------------|
| a. Very slowly | 0 | <1 km/year, highly localized |
| b. Rather slowly | 1 | 1-10 km/year |
| c. Rather quickly | 2 | 10-50 km/year |
| d. Quickly | 3 | >50 km/year, rapid range expansion |

**Consider:**
- Natural dispersal ability (flight, walking)
- Human-assisted spread potential
- Host/habitat connectivity
- Documented spread rates from invaded regions

**Example justification:**
> "In invaded North American range, spread rate documented at 40-80 km/year through combination of flight dispersal and movement with firewood. Continuous forest habitat in Norway would facilitate similar rates. **Score: d (Quickly)**"

---

### EST4: Facilitating Traits

**Question:** Does the species possess biological or ecological traits that could facilitate its establishment or spread in new areas?

| Option | Points | Interpretation |
|--------|--------|----------------|
| a. No it does not | 0 | No notable facilitating traits |
| b. To some extent | 1 | 1-2 minor facilitating traits |
| c. To a great extent | 2 | Multiple significant traits |
| d. To a very great extent | 3 | Highly invasive trait syndrome |

**Facilitating traits to consider:**
- Parthenogenesis or high fecundity
- Polyphagy (broad host/diet range)
- Long-distance dispersal ability
- Ability to survive without hosts (diapause, dormancy)
- Resistance to pesticides
- Adaptation to disturbed/urban habitats
- Association with human-modified environments

**Example justification:**
> "Species exhibits: (1) facultative parthenogenesis, (2) polyphagy across 50+ host species in 15 families, (3) flight capability >10 km, (4) adult survival >6 months without feeding. This trait combination strongly facilitates invasion. **Score: d (Very great extent)**"

---

## IMPACT Questions

### IMP1: Direct Economic Losses

**Question:** How significant are the direct economic losses that the species would cause in the risk assessment area?

| Option | Points | Annual losses (€) |
|--------|--------|------------------|
| a. No losses | 0 | 0 |
| b. | 0.5 | <50,000 |
| c. | 1 | 50,000-100,000 |
| d. | 1.5 | 100,000-200,000 |
| e. | 2 | 200,000-400,000 |
| f. | 2.5 | 400,000-800,000 |
| g. | 3 | 800,000-1.5 million |
| h. | 3.5 | 1.5-3 million |
| i. | 4 | 3-6 million |
| j. | 4.5 | 6-12 million |
| k. | 5 | 12-25 million |
| l. | 5.5 | 25-50 million |
| m. | 6 | >50 million |

**Consider:**
- Crop/forest production losses
- Control costs
- Replanting/replacement costs
- Infrastructure damage
- Tourism/recreation impacts

**Example justification:**
> "At 10% infestation of Norway's 30,000 ha commercial apple orchards, with 20% yield loss and €15,000/ha value, direct losses = €9 million/year. Plus €2 million control costs. Total: ~€11 million/year. **Score: j (6-12 million €)**"

---

### IMP2.1: Foreign Trade Impact

**Question:** Would the species impact foreign trade?

| Option | Points |
|--------|--------|
| Yes | 1 |
| No | 0 |

**Consider:**
- Would trading partners impose import restrictions?
- Is Norway a significant exporter of potentially affected commodities?
- Precedent from other invasive species trade impacts?

---

### IMP2.2: Vector for Other Pests

**Question:** Is the species a vector for other pests?

| Option | Points |
|--------|--------|
| Yes | 1 |
| No | 0 |

**Consider:**
- Known pathogen/parasite transmission
- Association with plant diseases
- Facilitation of secondary pest outbreaks

---

### IMP2.3: Sector Profitability Impact

**Question:** Would the species have a significant impact on the profitability of some plant production sector or ecosystem?

| Option | Points |
|--------|--------|
| Yes | 1 |
| No | 0 |

**Consider:**
- Specific sectors at risk (forestry, horticulture, agriculture)
- Scale of potential impact on sector economics

---

### IMP3: Ecosystem and Biodiversity Impact

**Question:** How significant would the species' direct impacts on natural ecosystems and native biodiversity be in the risk assessment area?

| Option | Points | Interpretation |
|--------|--------|----------------|
| a. No impact | 0 | No interaction with native ecosystems |
| b. Moderate | 2 | Localized effects, no threatened species affected |
| c. Significant | 4 | Widespread effects or threatened species affected |
| d. Very significant | 6 | Major ecosystem disruption, multiple threatened species |

**Consider:**
- Competition with native species
- Predation on native fauna
- Alteration of food webs
- Effects on threatened/protected species
- Ecosystem function disruption (pollination, decomposition)

**Example justification:**
> "Species preys on native pollinators (Bombus spp., solitary bees) and competes with native Vespidae. Three native bumblebee species in Norway are red-listed. Invasion could significantly reduce pollinator diversity and ecosystem pollination services. **Score: c (Significant impact)**"

---

### IMP4.1: Social Impacts

**Question:** Would the species have social impacts?

| Option | Points |
|--------|--------|
| Yes | 1 |
| No | 0 |

**Consider:**
- Human health risks (stings, bites, allergens)
- Nuisance in residential areas
- Fear/anxiety in public
- Impacts on outdoor activities

---

### IMP4.2: Aesthetic Impacts

**Question:** Would the species have significant aesthetic impacts?

| Option | Points |
|--------|--------|
| Yes | 1 |
| No | 0 |

**Consider:**
- Visible damage to ornamental plants
- Defoliation of landscape trees
- Impacts on gardens and parks
- Tourism and recreational area degradation

---

### IMP4.3: Cultural Heritage Impacts

**Question:** Would the species impact culturally important plants or other organisms?

| Option | Points |
|--------|--------|
| Yes | 1 |
| No | 0 |

**Consider:**
- Heritage trees, historic gardens
- Culturally significant species
- Traditional land use practices

---

## MANAGEMENT Questions

### MAN1: Natural Spread Potential

**Question:** Can the species spread naturally to the risk assessment area from its current range during the next ten years?

| Option | Points | Interpretation |
|--------|--------|----------------|
| a. No it cannot | 0 | Too far, barriers exist, no natural pathway |
| b. Can, but unlikely | 2 | Possible but slow, marginal conditions |
| c. Can, and likely/very likely | 4 | Active range expansion toward risk area |

**Consider:**
- Current distribution relative to risk assessment area
- Natural dispersal rate and direction
- Geographic barriers (seas, mountains)
- Climate corridor availability

**Example justification:**
> "Currently established in central Europe (Germany, Poland). At documented spread rate of 50 km/year, could reach Scandinavian peninsula in 10-15 years. Sea barrier requires human-mediated jump to Norway. **Score: b (Can, but unlikely)**"

---

### MAN2: EU Presence

**Question:** Is the species present in the area of the European Union?

| Option | Points | Interpretation |
|--------|--------|----------------|
| a. No it is not | 0 | Not present in EU |
| b. Yes, small area | 2 | Localized, few countries |
| c. Yes, large area | 3 | Widespread across multiple EU countries |

---

### MAN3: Detection Difficulty

**Question:** How difficult is it to detect the species during inspections of commodities or conveyances?

| Option | Points | Interpretation |
|--------|--------|----------------|
| a. Easy | 0 | Adults visible, distinctive signs |
| b. Difficult | 1 | Cryptic life stages, hidden in substrate |
| c. Nearly impossible | 2 | Microscopic, inside tissue, no visible signs |

**Consider:**
- Life stage most likely transported (eggs, larvae, adults)
- Visibility and distinctiveness
- Whether hidden inside host material
- Availability of detection methods

**Example justification:**
> "Transported primarily as eggs and early larvae inside wood. No external symptoms in early infestation. Detection requires destructive sampling or specialized acoustic/X-ray equipment not available at most inspection points. **Score: c (Nearly impossible)**"

---

### MAN4: Eradication Difficulty

**Question:** How difficult would it be to eradicate the species from the risk assessment area if established?

| Option | Points | Interpretation |
|--------|--------|----------------|
| a. Easy | 0 | Localized, effective tools available |
| b. Rather difficult | 2 | Feasible with significant effort |
| c. Very difficult | 3 | Major resources required, uncertain success |
| d. Impossible | 4 | Eradication not feasible once established |

**Consider:**
- Host/habitat extent and accessibility
- Reproductive rate and spread speed
- Effectiveness of control measures
- Precedent from eradication attempts elsewhere

**Example justification:**
> "Once established in forest ecosystems, the species is highly mobile with high reproductive output. Eradication attempts in North America and Asia have failed. Only early detection with immediate intensive response has succeeded. **Score: d (Impossible)**"

---

### MAN5: Survey Difficulty

**Question:** How difficult would it be to survey and monitor the species' occurrence in the risk assessment area?

| Option | Points | Interpretation |
|--------|--------|----------------|
| a. Easy | 0 | Distinctive, easily trapped/observed |
| b. Rather difficult | 1 | Requires specialized methods |
| c. Very difficult | 2 | Low detection probability, cryptic |
| d. Impossible | 3 | No effective survey methods |

**Consider:**
- Availability of pheromone lures or traps
- Visibility of damage symptoms
- Seasonal activity patterns
- Expertise required for identification

**Example justification:**
> "Effective pheromone lures available (commercial product X). Adults attracted to traps May-September. Distinctive wing pattern allows visual identification. Trapping network successfully used in EU monitoring programs. **Score: a (Easy)**"

---

## Quality Criteria for Justifications

Good justifications should:

1. **Cite specific evidence** - data sources, publications, monitoring records
2. **Be quantitative where possible** - numbers, percentages, areas
3. **Reference comparable situations** - invasions elsewhere, similar species
4. **Address uncertainty** - acknowledge data gaps, conflicting evidence
5. **Match the selected option** - conclusion follows from evidence presented

**Avoid:**
- Vague statements without evidence
- Circular reasoning
- Overly confident claims without support
- Ignoring contradictory evidence

---

## Data Sources

Recommended sources for evidence:
- **Distribution:** GBIF, CABI Invasive Species Compendium, EPPO Global Database
- **Interceptions:** Europhyt, national plant health records
- **Trade data:** Eurostat, national statistics
- **Climate:** WorldClim, climate matching tools (CLIMEX)
- **Biology:** Primary literature, CABI datasheets, EPPO datasheets
- **Impacts:** Case studies from invaded regions, economic assessments

---

## Reference

This framework is adapted from:

Heikkilä et al. (2016) *The FinnPRIO model: A model for ranking plant pests based on risk.* Biological Invasions 18:1827-1842.

BioPRIO adaptation for terrestrial invertebrates, 2026.
