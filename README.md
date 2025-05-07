### Flights map generator

Clone the repo, then in repo folder, add a JSON file named `flights.json` with your flights list in this format:

```json
[
  {"date": "08/10/2018", "from": "CDG", "to": "EWR"},
  {"date": "10/10/2018", "from": "EWR", "to": "PHX"},
  {"date": "17/10/2018", "from": "PHX", "to": "JFK"},
  {"date": "17/10/2018", "from": "JFK", "to": "CDG"},
  {"date": "30/12/2018", "from": "CDG", "to": "OSL"},
  {"date": "02/01/2019", "from": "OSL", "to": "CDG"},
  {"date": "03/01/2019", "from": "CDG", "to": "LAX"},
  {"date": "18/01/2019", "from": "SAN", "to": "SJC"},
  {"date": "20/01/2019", "from": "SJC", "to": "SAN"},
  {"date": "12/04/2019", "from": "LAX", "to": "CDG"}
]
```

- The file `departure_airports.txt` contains a space-separated list of your usual departure airports. These won't be shown in destinations list, and their codes won't show up on the map

- The file `cities.json` can be completed with your used airports to get the cities next to the codes in the destinations list

Then just run `ruby flight_map_generator.rb`

This will generate a SVG file `flight_map_with_base.svg` with your map
