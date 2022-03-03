# Swift Destination Plugin Template
This template is resolved around `ExampleDestination` (to be replaced by you). 

## What does the template provide
### Data class for holding settings
To standardize fetching and using settings in your destination, we recommend using a Coable class to store your destination settings. If marked `Codable`, it will enable you to retrieve your destination settings in a strongly typed construct.

### Settings-related functions
We provide APIs to update your destination settings in `update(settings:type:)`.
`UpdateType.initial` lets you know if this is the intial or subsequent fetch.

`Settings.isDestinationEnabled(key: String)`
- check if your destination is enabled

`Settings.integrationSettings(forKey: String)`
- retrieve a typed destination object

### Sample implementation for common destination functions
We have templated common destinations functions like `track`, `identify`, `screen`, `group`, `alias` that you should modify to fit your vendor SDK implementation. Although these functions do not need to return the ending payload, its good practice to do so (for unit testing purposes).

### Transforming events
Often times, destinations need to transform events (eg: change names, modify properties/traits etc.). We have templated an example of transformation in the `track(event:)` example. we recommend you use this approach to perform any such transformations. This will make your code more legible plus improve code quality.

### Testing functions for primary functions (to be expanded)
We have provided a very bare minimum template for testing the primary destination APIs. We recommend to use this as a starter and build upon it to get test coverage of most scenarios.
