# Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
#
# WSO2 LLC. licenses this file to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License. You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Generate the synthetic clinical-note dataset for the Jev gate experiment.

All identifiers are invented. Phone numbers use the 555-01xx reserved range,
emails use example.com, and addresses are fictional, so nothing here can map to
a real person. The file is deterministic: re-running produces identical bytes.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Callable

OUTPUT = Path(__file__).with_name("clinical_notes.jsonl")

OVERFLOW_FILLER = (
    "The patient tolerated the procedure well and vital signs remained stable throughout. "
)

PATIENTS: tuple[dict[str, str], ...] = (
    {
        "name": "Alice Nguyen",
        "mrn": "MRN-4100137",
        "dob": "1968-04-12",
        "phone": "+1-555-0100",
        "email": "alice.nguyen@example.com",
        "address": "742 Evergreen Terrace, Springfield",
        "insurance": "INS-4821-773",
    },
    {
        "name": "Marcus Bell",
        "mrn": "MRN-4100274",
        "dob": "1975-11-02",
        "phone": "+1-555-0101",
        "email": "marcus.bell@example.com",
        "address": "18 Birchwood Lane, Riverton",
        "insurance": "INS-4822-118",
    },
    {
        "name": "Priya Raman",
        "mrn": "MRN-4100411",
        "dob": "1990-07-23",
        "phone": "+1-555-0102",
        "email": "priya.raman@example.com",
        "address": "204 Cedar Court, Fairview",
        "insurance": "INS-4823-904",
    },
    {
        "name": "Daniel Okafor",
        "mrn": "MRN-4100548",
        "dob": "1959-01-30",
        "phone": "+1-555-0103",
        "email": "daniel.okafor@example.com",
        "address": "77 Maple Drive, Lakeside",
        "insurance": "INS-4824-556",
    },
    {
        "name": "Sofia Marchetti",
        "mrn": "MRN-4100685",
        "dob": "1983-09-14",
        "phone": "+1-555-0104",
        "email": "sofia.marchetti@example.com",
        "address": "9 Harbour Street, Portwell",
        "insurance": "INS-4825-231",
    },
    {
        "name": "Liam O'Connor",
        "mrn": "MRN-4100822",
        "dob": "2001-03-08",
        "phone": "+1-555-0105",
        "email": "liam.oconnor@example.com",
        "address": "31 Elm Row, Ashford",
        "insurance": "INS-4826-780",
    },
    {
        "name": "Hana Suzuki",
        "mrn": "MRN-4100959",
        "dob": "1971-12-19",
        "phone": "+1-555-0106",
        "email": "hana.suzuki@example.com",
        "address": "5 Willow Way, Greenfield",
        "insurance": "INS-4827-663",
    },
    {
        "name": "Omar Haddad",
        "mrn": "MRN-4110096",
        "dob": "1988-06-27",
        "phone": "+1-555-0107",
        "email": "omar.haddad@example.com",
        "address": "120 Pine Avenue, Brookside",
        "insurance": "INS-4828-442",
    },
    {
        "name": "Grace Mbeki",
        "mrn": "MRN-4110233",
        "dob": "1962-02-11",
        "phone": "+1-555-0108",
        "email": "grace.mbeki@example.com",
        "address": "64 Oak Crescent, Hilltop",
        "insurance": "INS-4829-015",
    },
    {
        "name": "Ethan Kowalski",
        "mrn": "MRN-4110370",
        "dob": "1994-10-05",
        "phone": "+1-555-0109",
        "email": "ethan.kowalski@example.com",
        "address": "3 Rowan Close, Eastwick",
        "insurance": "INS-4830-887",
    },
    {
        "name": "Isla Fraser",
        "mrn": "MRN-4110507",
        "dob": "1979-08-16",
        "phone": "+1-555-0110",
        "email": "isla.fraser@example.com",
        "address": "88 Heather Road, Northgate",
        "insurance": "INS-4831-329",
    },
    {
        "name": "Noah Petrov",
        "mrn": "MRN-4110644",
        "dob": "2005-05-21",
        "phone": "+1-555-0111",
        "email": "noah.petrov@example.com",
        "address": "12 Sycamore Street, Westbrook",
        "insurance": "INS-4832-674",
    },
    {
        "name": "Maya Krishnan",
        "mrn": "MRN-4110781",
        "dob": "1966-01-09",
        "phone": "+1-555-0112",
        "email": "maya.krishnan@example.com",
        "address": "45 Aspen Grove, Clearton",
        "insurance": "INS-4833-908",
    },
    {
        "name": "Lucas Fontaine",
        "mrn": "MRN-4110918",
        "dob": "1981-11-28",
        "phone": "+1-555-0113",
        "email": "lucas.fontaine@example.com",
        "address": "230 Beech Lane, Sunmead",
        "insurance": "INS-4834-142",
    },
    {
        "name": "Aisha Rahman",
        "mrn": "MRN-4120055",
        "dob": "1997-04-02",
        "phone": "+1-555-0114",
        "email": "aisha.rahman@example.com",
        "address": "16 Chestnut Walk, Highbury",
        "insurance": "INS-4835-530",
    },
    {
        "name": "Tomas Silva",
        "mrn": "MRN-4120192",
        "dob": "1954-09-07",
        "phone": "+1-555-0115",
        "email": "tomas.silva@example.com",
        "address": "101 Poplar Place, Meadowbank",
        "insurance": "INS-4836-266",
    },
    {
        "name": "Nina Bauer",
        "mrn": "MRN-4120329",
        "dob": "1973-06-13",
        "phone": "+1-555-0116",
        "email": "nina.bauer@example.com",
        "address": "7 Hazel Court, Stonebridge",
        "insurance": "INS-4837-771",
    },
    {
        "name": "Caleb Mensah",
        "mrn": "MRN-4120466",
        "dob": "1986-12-31",
        "phone": "+1-555-0117",
        "email": "caleb.mensah@example.com",
        "address": "59 Alder Avenue, Riverside",
        "insurance": "INS-4838-498",
    },
    {
        "name": "Ruth Alvarez",
        "mrn": "MRN-4120603",
        "dob": "1969-03-26",
        "phone": "+1-555-0118",
        "email": "ruth.alvarez@example.com",
        "address": "27 Laurel Drive, Kingsport",
        "insurance": "INS-4839-123",
    },
    {
        "name": "Kenji Tanaka",
        "mrn": "MRN-4120740",
        "dob": "1992-07-18",
        "phone": "+1-555-0119",
        "email": "kenji.tanaka@example.com",
        "address": "14 Magnolia Street, Baytown",
        "insurance": "INS-4840-655",
    },
)


def _referral(p: dict[str, str]) -> tuple[str, list[str]]:
    text = (
        f"Referral for {p['name']}, {p['mrn']}, DOB {p['dob']}. "
        f"Please assess for persistent cough. Contact {p['phone']} to schedule."
    )
    return text, [p["name"], p["mrn"], p["dob"], p["phone"]]


def _discharge(p: dict[str, str]) -> tuple[str, list[str]]:
    text = (
        f"Discharge summary for {p['name']} ({p['email']}). Admitted with chest pain, "
        f"now stable. Reach the patient at {p['phone']} or {p['address']}."
    )
    return text, [p["name"], p["email"], p["phone"], p["address"]]


def _lab(p: dict[str, str]) -> tuple[str, list[str]]:
    text = (
        f"{p['name']} (DOB {p['dob']}, {p['mrn']}) — HbA1c 7.8%, "
        f"LDL 3.1 mmol/L. Insurance {p['insurance']} on file."
    )
    return text, [p["name"], p["dob"], p["mrn"], p["insurance"]]


def _appointment(p: dict[str, str]) -> tuple[str, list[str]]:
    text = (
        f"Appointment reminder for {p['name']}. Call {p['phone']} to confirm. "
        f"Address on file: {p['address']}."
    )
    return text, [p["name"], p["phone"], p["address"]]


def _results_email(p: dict[str, str]) -> tuple[str, list[str]]:
    return f"Please send the results to {p['name']} at {p['email']}.", [p["name"], p["email"]]


def _name_dob(p: dict[str, str]) -> tuple[str, list[str]]:
    return f"Patient {p['name']}, date of birth {p['dob']}, reports dizziness on standing.", [
        p["name"],
        p["dob"],
    ]


def _full(p: dict[str, str]) -> tuple[str, list[str]]:
    text = (
        f"Patient {p['name']}, DOB {p['dob']}, {p['mrn']}, phone {p['phone']}, "
        f"email {p['email']}, address {p['address']}, insurance {p['insurance']}."
    )
    return text, [
        p["name"],
        p["dob"],
        p["mrn"],
        p["phone"],
        p["email"],
        p["address"],
        p["insurance"],
    ]


def _preauth(p: dict[str, str]) -> tuple[str, list[str]]:
    return (
        f"Pre-authorization requested for {p['name']}, policy {p['insurance']}, {p['mrn']}.",
        [p["name"], p["insurance"], p["mrn"]],
    )


def _home_visit(p: dict[str, str]) -> tuple[str, list[str]]:
    return (
        f"Home visit scheduled for {p['name']} at {p['address']}.",
        [p["name"], p["address"]],
    )


def _callback(p: dict[str, str]) -> tuple[str, list[str]]:
    return (
        f"Nurse call-back for {p['name']} at {p['phone']} regarding medication review.",
        [p["name"], p["phone"]],
    )


PII_TEMPLATES: tuple[Callable[[dict[str, str]], tuple[str, list[str]]], ...] = (
    _referral,
    _discharge,
    _lab,
    _appointment,
    _results_email,
    _name_dob,
    _full,
    _preauth,
    _home_visit,
    _callback,
)

NON_PII_TEXTS: tuple[str, ...] = (
    "Metformin 500 mg twice daily with meals; recheck HbA1c in 3 months.",
    "Follow up in two weeks if symptoms persist; return sooner if fever develops.",
    "Hand hygiene remains the most effective measure to reduce hospital-acquired infections.",
    "The patient education leaflet covers a low-sodium diet and daily weight monitoring.",
    "Influenza vaccination is recommended annually for adults over 65.",
    "Normal saline 0.9% is the preferred isotonic crystalloid for initial resuscitation.",
    "Please schedule the colonoscopy prep instructions to be mailed before the procedure.",
    "Blood pressure target for most adults is below 130/80 mmHg.",
    "Physical therapy twice weekly for six weeks to address lower back pain.",
    "The formulary lists amoxicillin as first-line for uncomplicated otitis media.",
    "Reminder: complete the annual infection-control training module by month end.",
    "Statin therapy reduces cardiovascular risk in patients with elevated LDL.",
    "Sleep hygiene counselling includes a consistent bedtime and reduced screen time.",
    "The clinic will be closed on the public holiday; on-call coverage is unchanged.",
    "Hydration and early mobilisation are encouraged after uncomplicated surgery.",
)


def _edge_records() -> list[dict[str, object]]:
    overflow_note, _ = _referral(PATIENTS[0])
    overflow_text = overflow_note + " " + OVERFLOW_FILLER * 3200
    return [
        {
            "id": "edge-001",
            "category": "edge",
            "has_pii": False,
            "entities": [],
            "text": "The World Health Organization reported a decline in global measles cases this year.",
        },
        {
            "id": "edge-002",
            "category": "edge",
            "has_pii": False,
            "entities": [],
            "text": "The wound check is due in three weeks; no fixed calendar date is set.",
        },
        {
            "id": "edge-003",
            "category": "edge",
            "has_pii": False,
            "entities": [],
            "text": "Prescribe lisinopril 10 mg daily and atorvastatin 20 mg nightly.",
        },
        {
            "id": "edge-004",
            "category": "edge",
            "has_pii": False,
            "entities": [],
            "text": "Vitals: temperature 37.1 C, heart rate 72, respiratory rate 14, SpO2 98%.",
        },
        {
            "id": "edge-005",
            "category": "edge",
            "has_pii": False,
            "entities": [],
            "text": "",
        },
        {
            "id": "edge-006",
            "category": "edge",
            "has_pii": False,
            "entities": [],
            "text": "   \n   ",
        },
        {
            "id": "edge-007",
            "category": "edge_long",
            "has_pii": False,
            "entities": [],
            "text": overflow_text,
        },
        {
            "id": "edge-008",
            "category": "edge",
            "has_pii": False,
            "entities": [],
            "text": "Recuerde beber suficiente agua y descansar; regrese si la fiebre continua.",
        },
        {
            "id": "edge-009",
            "category": "edge",
            "has_pii": True,
            "entities": ["Rose"],
            "text": "Rose felt much better after the infusion; her garden is her main hobby.",
        },
        {
            "id": "edge-010",
            "category": "edge",
            "has_pii": False,
            "entities": [],
            "text": "For appointments call the main hospital line at 1-800-555-0199.",
        },
    ]


def _pii_records() -> list[dict[str, object]]:
    records: list[dict[str, object]] = []
    for index in range(45):
        template = PII_TEMPLATES[index % len(PII_TEMPLATES)]
        patient = PATIENTS[index % len(PATIENTS)]
        text, entities = template(patient)
        records.append(
            {
                "id": f"pii-{index + 1:03d}",
                "category": "pii",
                "has_pii": True,
                "entities": entities,
                "text": text,
            }
        )
    return records


def _non_pii_records() -> list[dict[str, object]]:
    return [
        {
            "id": f"gen-{index + 1:03d}",
            "category": "no_pii",
            "has_pii": False,
            "entities": [],
            "text": NON_PII_TEXTS[index % len(NON_PII_TEXTS)],
        }
        for index in range(45)
    ]


def build_records() -> list[dict[str, object]]:
    return _pii_records() + _non_pii_records() + _edge_records()


def main() -> None:
    records = build_records()
    payload = "\n".join(json.dumps(record, ensure_ascii=False) for record in records)
    OUTPUT.write_text(payload + "\n", encoding="utf-8")
    pii = sum(1 for record in records if record["has_pii"])
    print(f"wrote {len(records)} records to {OUTPUT} ({pii} with PII, {len(records) - pii} without)")


if __name__ == "__main__":
    main()
