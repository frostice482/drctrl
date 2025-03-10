<div align=middle>
    <img src="./doc/img.jpg" width=250 height=250>
    <img src="./doc/oc.gif" width=250 height=250>
    <br>
    <b>drctrl</b>: advanced Draconic Evolution Reactor controller.
</div>

## Setup & Requirements

Known working versions:
- 1.20.1

Known incompatible versions:
- 1.7.10 (`string.format` for rounded float precision does not work, causing display issues)

Requirements:
- Advanced Computer
- 2 Flux gate
- Advanced monitor (optional, recommended size 3x3)
- Constant energy supply

To install, run `wget run https://raw.githubusercontent.com/frostice482/drctrl/refs/heads/master/install.lua`. You can also drag and drop the `install.lua` file and run it from there.

To configure peripherals, edit `peripherals_config`. By default:
- Reactor stabilizer: `top`
- Input gate: `back`
- Output gate: `right`
- Monitor: `monitor_0`

To run the controller, simply run `main`. By default, the controller will not start itself again after shutdown, so it is recommended to rename `main` to `startup`.

**Heads up!** Due to technical issues, your reactor may blow up anytime! This script cannot guarantee that your reactor will be safe. Please make a backup!

## Configuration

- Max Temperature

    Configures maximum temperature of the reactor. 8000 is recommended maximum. Higher will cause fuel consumption and field input to increase exponentially.

- Target Field

    Configures target field strength of the reactor. 50% is recommended value. Higher will use more energy. Lower will cause the reactor to prone to field drop because of temperature increase. Ranges from 5% to 99.9%.

- Max Input

    Configures how much energy can be put into the reactor constantly. Reactor's temperature will be limited by how much energy can be put at target field. This should be configured slightly less than the actual input limit. 10M RF/t is default value. Maximum depends on reactor's field strength

- Max Chaos

    Configures how much chaos should be within the reactor's fuel before automatic shutdown. 95% is default and maximum value.

Configuration file is saved to `drctrl_config`.
