import BattleKit

typealias TypeChart = BattleKit.TypeChart
typealias TypeMatchup = BattleKit.TypeMatchup

extension TypeChart {
    init(rows: [TypeDetail]) {
        var dict: [String: TypeMatchup] = [:]
        for row in rows {
            dict[row.name] = TypeMatchup(
                doubleDamageTo: row.doubleDamageTo,
                halfDamageTo: row.halfDamageTo,
                noDamageTo: row.noDamageTo
            )
        }
        self.init(attackers: dict)
    }
}
