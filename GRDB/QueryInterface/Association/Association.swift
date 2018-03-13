/// The base protocol for all associations that define a connection between two
/// Record types.
public protocol Association: SelectionRequest, FilteredRequest, OrderedRequest {
    associatedtype LeftAssociated: TableRecord
    associatedtype RightAssociated: TableRecord
    
    /// The association key defines how rows fetched from this association
    /// should be consumed.
    ///
    /// For example:
    ///
    ///     struct Player: TableRecord {
    ///         // The default key of this association is the name of the
    ///         // database table for teams, let's say "team":
    ///         static let team = belongsTo(Team.self)
    ///     }
    ///     print(Player.team.key) // Prints "team"
    ///
    ///     // Consume rows:
    ///     let request = Player.including(required: Player.team)
    ///     for row in Row.fetchAll(db, request) {
    ///         let team: Team = row["team"] // the association key
    ///     }
    ///
    /// The key can be redefined with the `forKey` method:
    ///
    ///     let request = Player.including(required: Player.team.forKey("custom"))
    ///     for row in Row.fetchAll(db, request) {
    ///         let team: Team = row["custom"]
    ///     }
    var key: String { get }
    
    /// Creates an association with the given key.
    ///
    /// This new key impacts how rows fetched from this association
    /// should be consumed:
    ///
    ///     struct Player: TableRecord {
    ///         static let team = belongsTo(Team.self)
    ///     }
    ///
    ///     // Consume rows:
    ///     let request = Player.including(required: Player.team.forKey("custom"))
    ///     for row in Row.fetchAll(db, request) {
    ///         let team: Team = row["custom"]
    ///     }
    func forKey(_ key: String) -> Self
    
    /// :nodoc:
    var request: AssociationRequest<RightAssociated> { get }
    
    /// :nodoc:
    func associationMapping(_ db: Database) throws -> AssociationMapping
    
    /// :nodoc:
    func mapRequest(_ transform: (AssociationRequest<RightAssociated>) -> AssociationRequest<RightAssociated>) -> Self
}

func defaultAssociationKey<T: TableRecord>(for type: T.Type) -> String {
    return T.databaseTableName
}

extension Association {
    func mapQuery(_ transform: @escaping DatabaseTransform<AssociationQuery>) -> Self {
        return mapRequest { $0.mapQuery(transform) }
    }
    
    func mapQueryChain(_ transform: @escaping DatabaseTransform<AssociationQuery>) -> Self {
        return mapRequest { $0.mapQueryChain(transform) }
    }
}

extension Association {
    /// Creates an association with a new net of selected columns.
    ///
    /// Any previous selection is replaced.
    public func select(_ selection: [SQLSelectable]) -> Self {
        return mapQuery { (_, query) in query.select(selection) }
    }
    
    /// Creates an association with columns appended to the selection.
    public func annotate(with selection: [SQLSelectable]) -> Self {
        return mapQuery { (_, query) in query.annotate(with: selection) }
    }
    
    /// Creates an association with the provided *predicate* added to the
    /// eventual set of already applied predicates.
    public func filter(_ predicate: SQLExpressible) -> Self {
        return mapQuery { (_, query) in query.filter(predicate) }
    }
    
    /// Creates an association with the provided primary key *predicate*.
    public func filter<PrimaryKeyType: DatabaseValueConvertible>(key: PrimaryKeyType?) -> Self {
        return mapRequest { $0.filter(key: key) }
    }
    
    /// Creates an association with the provided primary key *predicate*.
    public func filter<Sequence: Swift.Sequence>(keys: Sequence) -> Self where Sequence.Element: DatabaseValueConvertible {
        return mapRequest { $0.filter(keys: keys) }
    }
    
    /// Creates an association with the provided primary key *predicate*.
    ///
    /// When executed, this request raises a fatal error if there is no unique
    /// index on the key columns.
    public func filter(key: [String: DatabaseValueConvertible?]?) -> Self {
        return mapRequest { $0.filter(key: key) }
    }
    
    /// Creates an association with the provided primary key *predicate*.
    ///
    /// When executed, this request raises a fatal error if there is no unique
    /// index on the key columns.
    public func filter(keys: [[String: DatabaseValueConvertible?]]) -> Self {
        return mapRequest { $0.filter(keys: keys) }
    }
    
    /// Creates an association that matches nothing.
    public func none() -> Self {
        return mapQuery { (_, query) in query.none() }
    }
    
    /// Creates an association with the provided *orderings*.
    ///
    /// Any previous ordering is replaced.
    public func order(_ orderings: [SQLOrderingTerm]) -> Self {
        return mapQuery { (_, query) in query.order(orderings) }
    }
    
    /// Creates an association that reverses applied orderings. If no ordering
    /// was applied, the returned request is identical.
    public func reversed() -> Self {
        return mapQuery { (_, query) in query.reversed() }
    }
    
    /// Creates an association with the given key.
    ///
    /// This new key helps Decodable records decode fetched rows:
    ///
    ///     struct Player: TableRecord {
    ///         static let team = belongsTo(Team.self)
    ///     }
    ///
    ///     struct PlayerInfo: FetchableRecord, Decodable {
    ///         let player: Player
    ///         let team: Team
    ///
    ///         static func all() -> AnyFetchRequest<PlayerInfo> {
    ///             return Player
    ///                 .including(required: Player.team.forKey(CodingKeys.team))
    ///                 .asRequest(of: PlayerInfo.self)
    ///         }
    ///     }
    ///
    ///     let playerInfos = PlayerInfo.all().fetchAll(db)
    ///     print(playerInfos.first?.team)
    public func forKey(_ codingKey: CodingKey) -> Self {
        return forKey(codingKey.stringValue)
    }

    /// Creates an association that allows you to define unambiguous expressions
    /// based on the associated record.
    ///
    /// In the example below, the "team.color = 'red'" condition in the where
    /// clause could be not achieved without table aliases.
    ///
    ///     struct Player: TableRecord {
    ///         static let team = belongsTo(Team.self)
    ///     }
    ///
    ///     // SELECT player.*, team.*
    ///     // JOIN team ON ...
    ///     // WHERE team.color = 'red'
    ///     let teamAlias = TableAlias()
    ///     let request = Player
    ///         .including(required: Player.team.aliased(teamAlias))
    ///         .filter(teamAlias[Column("color"] == "red")
    ///
    /// When you give a name to a table alias, you can reliably inject sql
    /// snippets in your requests:
    ///
    ///     // SELECT player.*, custom.*
    ///     // JOIN team custom ON ...
    ///     // WHERE custom.color = 'red'
    ///     let teamAlias = TableAlias(name: "custom")
    ///     let request = Player
    ///         .including(required: Player.team.aliased(teamAlias))
    ///         .filter(sql: "custom.color = ?", arguments: ["red")
    public func aliased(_ alias: TableAlias) -> Self {
        return mapQuery { (_, query) in
            let userProvidedAlias = alias.userProvidedAlias
            defer {
                // Allow user to explicitely rename (TODO: test)
                alias.userProvidedAlias = userProvidedAlias
            }
            return query.qualified(with: &alias.qualifier)
        }
    }
}

/// Not to be mismatched with SQLJoinOperator (inner, left)
///
/// AssociationChainOperator is designed to be hierarchically nested, unlike
/// SQL join operators.
///
/// Consider the following request for (A, B, C) tuples:
///
///     let r = A.including(optional: A.b.including(required: B.c))
///
/// It chains three associations, the first optional, the second required.
///
/// It looks like it means: "Give me all As, along with their Bs, granted those
/// Bs have their Cs. For As whose B has no C, give me a nil B".
///
/// It can not be expressed as one left join, and a regular join, as below,
/// Because this would not honor the first optional:
///
///     -- dubious
///     SELECT a.*, b.*, c.*
///     FROM a
///     LEFT JOIN b ON ...
///     JOIN c ON ...
///
/// Instead, it should:
/// - allow (A + missing (B + C))
/// - prevent (A + (B + missing C)).
///
/// This can be expressed in SQL with two left joins, and an extra condition:
///
///     -- likely correct
///     SELECT a.*, b.*, c.*
///     FROM a
///     LEFT JOIN b ON ...
///     LEFT JOIN c ON ...
///     WHERE NOT((b.id IS NOT NULL) AND (c.id IS NULL)) -- no B without C
///
/// This is currently not implemented, and requires a little more thought.
/// I don't even know if inventing a whole new way to perform joins should even
/// be on the table. But we have a hierarchical way to express joined queries,
/// and they have a meaning:
///
///     // what is my meaning?
///     A.including(optional: A.b.including(required: B.c))
enum AssociationChainOperator {
    case required, optional
}

extension Association {
    func chain<A: Association>(_ chainOp: AssociationChainOperator, _ association: A) -> Self
        where A.LeftAssociated == RightAssociated
    {
        return mapQueryChain { (db, leftQuery) in
            // FIXME: if joinOp is left, then association.request.query should only use left joins,
            // and turn the inner joins into (primary key is not null) requirements
            let rightQuery = try association.request.query(db)
            return try leftQuery.chaining(
                db: db,
                chainOp: chainOp,
                rightQuery: rightQuery,
                rightKey: association.key,
                mapping: association.associationMapping(db))
        }
    }
    
    /// Creates an association that includes another one. The columns of the
    /// associated record are selected. The returned association does not
    /// require that the associated database table contains a matching row.
    public func including<A: Association>(optional association: A) -> Self where A.LeftAssociated == RightAssociated
    {
        return chain(.optional, association)
    }
    
    /// Creates an association that includes another one. The columns of the
    /// associated record are selected. The returned association requires
    /// that the associated database table contains a matching row.
    public func including<A: Association>(required association: A) -> Self where A.LeftAssociated == RightAssociated
    {
        return chain(.required, association)
    }
    
    /// Creates an association that joins another one. The columns of the
    /// associated record are not selected. The returned association does not
    /// require that the associated database table contains a matching row.
    public func joining<A: Association>(optional association: A) -> Self where A.LeftAssociated == RightAssociated
    {
        return chain(.optional, association.select([]))
    }
    
    /// Creates an association that joins another one. The columns of the
    /// associated record are not selected. The returned association requires
    /// that the associated database table contains a matching row.
    public func joining<A: Association>(required association: A) -> Self where A.LeftAssociated == RightAssociated
    {
        return chain(.required, association.select([]))
    }
}