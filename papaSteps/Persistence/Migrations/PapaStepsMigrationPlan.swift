import SwiftData

enum PapaStepsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            PapaStepsSchemaV1.self,
            PapaStepsSchemaV2.self,
            PapaStepsSchemaV3.self,
            PapaStepsSchemaV4.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: PapaStepsSchemaV1.self,
                toVersion: PapaStepsSchemaV2.self
            ),
            .lightweight(
                fromVersion: PapaStepsSchemaV2.self,
                toVersion: PapaStepsSchemaV3.self
            ),
            .lightweight(
                fromVersion: PapaStepsSchemaV3.self,
                toVersion: PapaStepsSchemaV4.self
            )
        ]
    }
}
