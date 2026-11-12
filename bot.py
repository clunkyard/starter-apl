# A GNU APL tactic using the arena's installed core binding.
# Read tactic.apl first.
import math
from pathlib import Path

import clunkyard as cy
import clunkyard_apl


class Starter(clunkyard_apl.Tactic):
    def on_turn(self):
        super().on_turn()


if __name__ == "__main__":
    robot = Starter(str(Path(__file__).with_name("tactic.apl")))
    try:
        cy.run(robot, binding_name="clunkyard-apl")
    finally:
        robot.apl.close()
