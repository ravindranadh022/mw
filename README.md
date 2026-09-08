Pharmacy

const http = require("http");
const { URL } = require("url");
const { ObjectId } = require("mongodb");

const { connectDB, getDB } = require("./db");

const {
    sendJson,
    readJson,
    normalizeText
} = require("./utils");

const {
    createSession,
    setSessionCookie,
    clearSessionCookie,
    requireAuth,
    requireRole,
    deleteSession
} = require("./auth");

const PORT = 3000;


// --------------------------------------------------
// ObjectId validation
// --------------------------------------------------

function isValidObjectId(value) {
    return ObjectId.isValid(value) &&
        String(new ObjectId(value)) === value;
}


// --------------------------------------------------
// Route 1 - Login
// POST /login
// --------------------------------------------------

async function login(req, res) {
    const { email, password } = await readJson(req);
    if (!email || !password) {
        return sendJson(res, 400, {
            error: "email and password are required"
        });
    }
    const db = getDB();
    const user = await db.collection("users").findOne({
        email: email.toLowerCase()
    });
    if (!user || user.password !== password) {
        return sendJson(res, 401, {
            error: "Invalid credentials"
        });
    }
    const token = createSession(user);
    setSessionCookie(res, token);
    return sendJson(res, 200, {
        message: "Login successful",
        role: user.role,
        name: user.name
    });
}


// --------------------------------------------------
// Route 2 - Logout
// POST /logout
// --------------------------------------------------

async function logout(req, res) {

    const session = requireAuth(req, res);

    if (!session) {
        return;
    }

    deleteSession(session.token);

    clearSessionCookie(res);

    return sendJson(res, 200, {
        message: "Logout successful"
    });
}


// --------------------------------------------------
// Route 3 - Health
// GET /health
// --------------------------------------------------

function health(req, res) {

    return sendJson(res, 200, {
        status: "ok"
    });
}


// --------------------------------------------------
// Route 4 - View Current Session
// GET /session
// --------------------------------------------------

function sessionInfo(req, res) {

    const session = requireAuth(req, res);

    if (!session) {
        return;
    }

    return sendJson(res, 200, {
        userId: session.userId,
        name: session.name,
        role: session.role,
        expiresAt: session.expiresAt
    });
}


// --------------------------------------------------
// Route 5 - View Medicines
// GET /medicines
// --------------------------------------------------

async function getMedicines(req, res) {

    const session = requireRole(
        req,
        res,
        ["admin", "doctor", "pharmacist"]
    );

    if (!session) {
        return;
    }

    const db = getDB();

    const query = {};

    const active = req.parsedUrl.searchParams.get("active");

    if (active === "true") {
        query.active = true;
    }

    if (active === "false") {
        query.active = false;
    }

    const medicines = await db.collection("medicines")
        .find(query)
        .project({
            _id: 1,
            name: 1,
            code: 1,
            stock: 1,
            price: 1,
            active: 1
        })
        .sort({
            name: 1
        })
        .toArray();

    return sendJson(res, 200, medicines);
}


// --------------------------------------------------
// Route 6 - View Patients
// GET /patients
// --------------------------------------------------

async function getPatients(req, res) {

    const session = requireRole(
        req,
        res,
        ["admin", "doctor", "pharmacist"]
    );

    if (!session) {
        return;
    }

    const db = getDB();

    const patients = await db.collection("patients")
        .find({
            active: true
        })
        .project({
            _id: 1,
            name: 1,
            age: 1,
            phone: 1
        })
        .sort({
            name: 1
        })
        .toArray();

    return sendJson(res, 200, patients);
}


// --------------------------------------------------
// Route 7 - Create Prescription
// POST /prescriptions
// Doctor + Admin
// --------------------------------------------------

async function createPrescription(req, res) {

    const session = requireRole(
        req,
        res,
        ["doctor", "admin"]
    );

    if (!session) {
        return;
    }

    const body = await readJson(req);

    const patientId = normalizeText(body.patientId);
    const medicineId = normalizeText(body.medicineId);
    const dosage = normalizeText(body.dosage);
    const notes = body.notes;
    const quantity = body.quantity;

    let doctorId;

    // Doctor identity comes from session
    if (session.role === "doctor") {
        doctorId = session.userId;
    }

    // Admin must provide doctorId
    if (session.role === "admin") {
        doctorId = normalizeText(body.doctorId);
    }

    // Validate required IDs
    if (
        !patientId ||
        !medicineId ||
        !isValidObjectId(patientId) ||
        !isValidObjectId(medicineId)
    ) {
        return sendJson(res, 400, {
            error: "Invalid patientId or medicineId"
        });
    }

    // Admin doctorId validation
    if (
        session.role === "admin" &&
        (!doctorId || !isValidObjectId(doctorId))
    ) {
        return sendJson(res, 400, {
            error: "Invalid doctorId"
        });
    }

    // Dosage required
    if (!dosage) {
        return sendJson(res, 400, {
            error: "dosage is required"
        });
    }

    // Quantity must be positive integer
    if (
        !Number.isInteger(quantity) ||
        quantity <= 0
    ) {
        return sendJson(res, 400, {
            error: "quantity must be a positive integer"
        });
    }

    const db = getDB();

    // Find active patient
    const patient = await db.collection("patients").findOne({
        _id: new ObjectId(patientId),
        active: true
    });

    if (!patient) {
        return sendJson(res, 404, {
            error: "Patient not found"
        });
    }

    // Find active medicine
    const medicine = await db.collection("medicines").findOne({
        _id: new ObjectId(medicineId),
        active: true
    });

    if (!medicine) {
        return sendJson(res, 404, {
            error: "Medicine not found"
        });
    }

    // Find doctor
    const doctor = await db.collection("users").findOne({
        _id: new ObjectId(doctorId),
        role: "doctor"
    });

    if (!doctor) {
        return sendJson(res, 404, {
            error: "Doctor not found"
        });
    }

    const now = new Date();

    const prescription = {
        doctorId: doctor._id,
        doctorName: doctor.name,

        patientId: patient._id,
        patientName: patient.name,

        medicineId: medicine._id,
        medicineName: medicine.name,

        dosage: dosage,
        quantity: quantity,
        notes: notes,

        status: "pending",

        createdAt: now,
        updatedAt: now
    };

    const result = await db.collection("prescriptions")
        .insertOne(prescription);

    return sendJson(res, 201, {
        message: "Prescription created",
        prescriptionId: result.insertedId
    });
}


// --------------------------------------------------
// Route 8 - Read Prescriptions
// GET /prescriptions
// Pharmacist + Admin
// --------------------------------------------------

async function getPrescriptions(req, res) {

    const session = requireRole(
        req,
        res,
        ["pharmacist", "admin"]
    );

    if (!session) {
        return;
    }

    const db = getDB();

    // ----------------------------------------------
    // Pharmacist behavior
    // ----------------------------------------------

    if (session.role === "pharmacist") {

        const query = {
            status: "pending"
        };

        const medicineId =
            req.parsedUrl.searchParams.get("medicineId");

        if (medicineId) {

            if (!isValidObjectId(medicineId)) {
                return sendJson(res, 400, {
                    error: "Invalid medicineId filter"
                });
            }

            query.medicineId = new ObjectId(medicineId);
        }

        const prescriptions =
            await db.collection("prescriptions")
                .find(query)
                .project({
                    doctorName: 1,
                    patientName: 1,
                    medicineName: 1,
                    dosage: 1,
                    quantity: 1,
                    notes: 1,
                    status: 1,
                    createdAt: 1
                })
                .sort({
                    createdAt: 1,
                    patientName: 1
                })
                .toArray();

        return sendJson(res, 200, prescriptions);
    }


    // ----------------------------------------------
    // Admin behavior
    // ----------------------------------------------

    const query = {};

    const status =
        req.parsedUrl.searchParams.get("status");

    if (status) {

        const allowedStatuses = [
            "pending",
            "cancelled",
            "dispensed"
        ];

        if (!allowedStatuses.includes(status)) {
            return sendJson(res, 400, {
                error: "Invalid status filter"
            });
        }

        query.status = status;
    }

    const prescriptions =
        await db.collection("prescriptions")
            .find(query)
            .sort({
                createdAt: 1
            })
            .toArray();

    return sendJson(res, 200, prescriptions);
}


// --------------------------------------------------
// Route 9 - Update / Dispense Prescription
// PUT /prescriptions/:prescriptionId
// Pharmacist + Admin
// --------------------------------------------------

async function updatePrescription(req, res, prescriptionId) {

    // ----------------------------------------------
    // Validate prescription ID inside handler
    // ----------------------------------------------

    if (!isValidObjectId(prescriptionId)) {

        return sendJson(res, 400, {
            error: "Invalid prescription ID"
        });
    }

    const session = requireRole(
        req,
        res,
        ["pharmacist", "admin"]
    );

    if (!session) {
        return;
    }

    const db = getDB();

    const prescriptionObjectId =
        new ObjectId(prescriptionId);


    // ----------------------------------------------
    // Pharmacist = Dispense workflow
    // ----------------------------------------------

    if (session.role === "pharmacist") {

        const prescription =
            await db.collection("prescriptions").findOne({
                _id: prescriptionObjectId,
                status: "pending"
            });

        if (!prescription) {
            return sendJson(res, 404, {
                error: "Pending prescription not found"
            });
        }

        // Atomically reduce stock only when:
        // medicine is active
        // AND stock >= requested quantity

        const stockResult =
            await db.collection("medicines").updateOne(
                {
                    _id: prescription.medicineId,
                    active: true,
                    stock: {
                        $gte: prescription.quantity
                    }
                },
                {
                    $inc: {
                        stock: -prescription.quantity
                    }
                }
            );

        // Stock insufficient
        if (stockResult.matchedCount === 0) {

            return sendJson(res, 409, {
                error: "Insufficient medicine stock"
            });
        }


        // Update prescription from pending to dispensed

        const now = new Date();

        const prescriptionResult =
            await db.collection("prescriptions").updateOne(
                {
                    _id: prescriptionObjectId,
                    status: "pending"
                },
                {
                    $set: {
                        status: "dispensed",
                        pharmacistId: new ObjectId(session.userId),
                        pharmacistName: session.name,
                        dispensedAt: now,
                        updatedAt: now
                    }
                }
            );


        // Race condition:
        // another process updated prescription first

        if (prescriptionResult.matchedCount === 0) {

            // Restore the medicine stock
            await db.collection("medicines").updateOne(
                {
                    _id: prescription.medicineId
                },
                {
                    $inc: {
                        stock: prescription.quantity
                    }
                }
            );

            return sendJson(res, 409, {
                error: "Prescription was already updated"
            });
        }

        return sendJson(res, 200, {
            message: "Prescription dispensed"
        });
    }


    // ----------------------------------------------
    // Admin = Normal prescription update
    // ----------------------------------------------

    const body = await readJson(req);

    const updateFields = {};


    // dosage
    if (Object.prototype.hasOwnProperty.call(body, "dosage")) {

        const dosage = normalizeText(body.dosage);

        if (!dosage) {
            return sendJson(res, 400, {
                error: "dosage cannot be empty"
            });
        }

        updateFields.dosage = dosage;
    }


    // quantity
    if (Object.prototype.hasOwnProperty.call(body, "quantity")) {

        if (
            !Number.isInteger(body.quantity) ||
            body.quantity <= 0
        ) {
            return sendJson(res, 400, {
                error: "quantity must be a positive integer"
            });
        }

        updateFields.quantity = body.quantity;
    }


    // notes
    if (Object.prototype.hasOwnProperty.call(body, "notes")) {
        updateFields.notes = body.notes;
    }


    // status
    if (Object.prototype.hasOwnProperty.call(body, "status")) {

        const allowedStatuses = [
            "pending",
            "cancelled",
            "dispensed"
        ];

        if (!allowedStatuses.includes(body.status)) {
            return sendJson(res, 400, {
                error: "Invalid status"
            });
        }

        updateFields.status = body.status;
    }


    // At least one valid field is required

    if (Object.keys(updateFields).length === 0) {

        return sendJson(res, 400, {
            error: "At least one valid field is required"
        });
    }


    updateFields.updatedAt = new Date();


    const result =
        await db.collection("prescriptions").updateOne(
            {
                _id: prescriptionObjectId
            },
            {
                $set: updateFields
            }
        );


    if (result.matchedCount === 0) {

        return sendJson(res, 404, {
            error: "Prescription not found"
        });
    }

    return sendJson(res, 200, {
        message: "Prescription updated"
    });
}


// --------------------------------------------------
// Route 10 - Delete Prescription
// DELETE /prescriptions/:prescriptionId
// Admin only
// --------------------------------------------------

async function deletePrescription(req, res, prescriptionId) {

    // Validate ID inside handler

    if (!isValidObjectId(prescriptionId)) {

        return sendJson(res, 400, {
            error: "Invalid prescription ID"
        });
    }

    const session = requireRole(
        req,
        res,
        ["admin"]
    );

    if (!session) {
        return;
    }

    const db = getDB();

    const result =
        await db.collection("prescriptions").deleteOne({
            _id: new ObjectId(prescriptionId)
        });

    if (result.deletedCount === 0) {

        return sendJson(res, 404, {
            error: "Prescription not found"
        });
    }

    return sendJson(res, 200, {
        message: "Prescription deleted"
    });
}


// ==================================================
// SERVER
// ==================================================

const server = http.createServer(async (req, res) => {

    try {

        // Parse URL
        const parsedUrl = new URL(
            req.url,
            `http://${req.headers.host}`
        );

        // Store parsed URL on request
        req.parsedUrl = parsedUrl;

        // Normalize trailing slash
        let pathname = parsedUrl.pathname;

        if (
            pathname.length > 1 &&
            pathname.endsWith("/")
        ) {
            pathname = pathname.slice(0, -1);
        }


        // ------------------------------------------
        // Route 1
        // POST /login
        // ------------------------------------------

        if (
            req.method === "POST" &&
            pathname === "/login"
        ) {
            return await login(req, res);
        }


        // ------------------------------------------
        // Route 2
        // POST /logout
        // ------------------------------------------

        if (
            req.method === "POST" &&
            pathname === "/logout"
        ) {
            return await logout(req, res);
        }


        // ------------------------------------------
        // Route 3
        // GET /health
        // ------------------------------------------

        if (
            req.method === "GET" &&
            pathname === "/health"
        ) {
            return health(req, res);
        }


        // ------------------------------------------
        // Route 4
        // GET /session
        // ------------------------------------------

        if (
            req.method === "GET" &&
            pathname === "/session"
        ) {
            return sessionInfo(req, res);
        }


        // ------------------------------------------
        // Route 5
        // GET /medicines
        // ------------------------------------------

        if (
            req.method === "GET" &&
            pathname === "/medicines"
        ) {
            return await getMedicines(req, res);
        }


        // ------------------------------------------
        // Route 6
        // GET /patients
        // ------------------------------------------

        if (
            req.method === "GET" &&
            pathname === "/patients"
        ) {
            return await getPatients(req, res);
        }


        // ------------------------------------------
        // Route 7
        // POST /prescriptions
        // ------------------------------------------

        if (
            req.method === "POST" &&
            pathname === "/prescriptions"
        ) {
            return await createPrescription(req, res);
        }


        // ------------------------------------------
        // Route 8
        // GET /prescriptions
        // ------------------------------------------

        if (
            req.method === "GET" &&
            pathname === "/prescriptions"
        ) {
            return await getPrescriptions(req, res);
        }


        // ------------------------------------------
        // Dynamic prescription routes
        // PUT /prescriptions/:prescriptionId
        // DELETE /prescriptions/:prescriptionId
        // ------------------------------------------

        const prescriptionMatch =
            pathname.match(
                /^\/prescriptions\/([^/]+)$/
            );

        if (prescriptionMatch) {

            const prescriptionId =
                prescriptionMatch[1];

            // Route 9
            if (req.method === "PUT") {

                return await updatePrescription(
                    req,
                    res,
                    prescriptionId
                );
            }

            // Route 10
            if (req.method === "DELETE") {

                return await deletePrescription(
                    req,
                    res,
                    prescriptionId
                );
            }
        }


        // ------------------------------------------
        // No route matched
        // ------------------------------------------

        return sendJson(res, 404, {
            error: "Route not found"
        });

    } catch (err) {

        console.error(err);

        return sendJson(res, 500, {
            error: "Internal server error"
        });
    }
});


// ==================================================
// DATABASE CONNECTION + SERVER START
// ==================================================

async function startServer() {

    try {

        await connectDB();

        server.listen(PORT, () => {

            console.log(
                `Server running on http://localhost:${PORT}`
            );

        });

    } catch (err) {

        console.error(
            "Failed to start server:",
            err
        );
    }
}

startServer();

Online

const http = require("http");

const { URL } = require("url");

const { ObjectId } = require("mongodb");

const { connectDB, getDB } = require("./db");

const {
    sendJson,
    readJson,
    normalizeText
} = require("./utils");

const {
    createSession,
    requireAuth,
    requireRole,
    deleteSession
} = require("./auth");

const PORT = 3000;


// ==================================================
// CORS
// ==================================================

const allowedOrigins = new Set([
    "http://localhost:5500",
    "http://127.0.0.1:5500"
]);


function applyCors(req, res) {
    const origin = req.headers.origin;
    if (origin && allowedOrigins.has(origin)) {
        res.setHeader(
            "Access-Control-Allow-Origin",
            origin
        );
        res.setHeader(
            "Access-Control-Allow-Headers",
            "Content-Type, Authorization"
        );
        res.setHeader(
            "Access-Control-Allow-Methods",
            "GET, POST, PUT, DELETE, OPTIONS"
        );
        res.setHeader(
            "Vary",
            "Origin"
        );
    }
}


// ==================================================
// ObjectId validation
// ==================================================

function isValidObjectId(value) {

    return ObjectId.isValid(value) &&
        String(new ObjectId(value)) === value;
}


// ==================================================
// Route 1
// POST /login
// ==================================================

async function login(req, res) {
    const { email, password } = await readJson(req);
    if (!email || !password) {

        return sendJson(res, 400, {
            error: "email and password are required"
        });
    }
    const db = getDB();
    const user =
        await db.collection("users").findOne({
            email: email.toLowerCase()
        });
    if (!user || user.password !== password) {

        return sendJson(res, 401, {
            error: "Invalid credentials"
        });
    }
    const token = createSession(user);
    return sendJson(res, 200, {
        message: "Login successful",
        token: token,
        role: user.role
    });
}


// ==================================================
// Route 2
// POST /logout
// ==================================================

async function logout(req, res) {

    const session = requireAuth(req, res);


    if (!session) {
        return;
    }


    deleteSession(session.token);


    return sendJson(res, 200, {
        message: "Logged out"
    });
}


// ==================================================
// Route 3
// GET /health
// ==================================================

function health(req, res) {

    return sendJson(res, 200, {
        status: "ok"
    });
}


// ==================================================
// Route 4
// GET /session
// ==================================================

function getSessionInfo(req, res) {

    const session = requireAuth(req, res);


    if (!session) {
        return;
    }


    return sendJson(res, 200, {

        userId: session.userId,

        name: session.name,

        role: session.role,

        expiresAt: session.expiresAt
    });
}


// ==================================================
// Route 5
// GET /subjects
// ==================================================

async function getSubjects(req, res) {

    const session = requireAuth(req, res);


    if (!session) {
        return;
    }


    const db = getDB();


    const subjects =
        await db.collection("subjects")
            .find({})
            .project({
                _id: 0,
                code: 1,
                name: 1
            })
            .sort({
                code: 1
            })
            .toArray();


    return sendJson(res, 200, subjects);
}


// ==================================================
// Route 6
// GET /instructors
// ==================================================

async function getInstructors(req, res) {

    const session = requireAuth(req, res);


    if (!session) {
        return;
    }


    const db = getDB();


    const instructors =
        await db.collection("users")
            .find({
                role: "instructor"
            })
            .project({
                password: 0
            })
            .sort({
                name: 1
            })
            .toArray();


    return sendJson(res, 200, instructors);
}


// ==================================================
// Route 7
// POST /exams
// Instructor + Admin
// ==================================================

async function createExam(req, res) {

    const session = requireRole(
        req,
        res,
        ["instructor", "admin"]
    );


    if (!session) {
        return;
    }


    const body = await readJson(req);


    const title =
        normalizeText(body.title);

    const subjectCode =
        normalizeText(body.subjectCode);

    const durationMinutes =
        body.durationMinutes;

    const totalMarks =
        body.totalMarks;

    const scheduledAt =
        body.scheduledAt;


    // ----------------------------------------------
    // Validate title
    // ----------------------------------------------

    if (!title) {

        return sendJson(res, 400, {
            error: "title is required"
        });
    }


    // ----------------------------------------------
    // Validate subjectCode
    // ----------------------------------------------

    if (!subjectCode) {

        return sendJson(res, 400, {
            error: "subjectCode is required"
        });
    }


    // ----------------------------------------------
    // Validate duration
    // ----------------------------------------------

    if (
        !Number.isInteger(durationMinutes) ||
        durationMinutes <= 0
    ) {

        return sendJson(res, 400, {
            error:
                "durationMinutes must be a positive integer"
        });
    }


    // ----------------------------------------------
    // Validate totalMarks
    // ----------------------------------------------

    if (
        typeof totalMarks !== "number" ||
        totalMarks <= 0
    ) {

        return sendJson(res, 400, {
            error:
                "totalMarks must be greater than 0"
        });
    }


    // ----------------------------------------------
    // Validate scheduledAt
    // ----------------------------------------------

    const examDate =
        new Date(scheduledAt);


    if (
        !scheduledAt ||
        Number.isNaN(examDate.getTime()) ||
        examDate <= new Date()
    ) {

        return sendJson(res, 400, {
            error:
                "scheduledAt must be a valid future date/time"
        });
    }


    const db = getDB();


    // ----------------------------------------------
    // Check subject exists
    // ----------------------------------------------

    const subject =
        await db.collection("subjects").findOne({
            code: subjectCode
        });


    if (!subject) {

        return sendJson(res, 404, {
            error: "Subject not found"
        });
    }


    // ----------------------------------------------
    // Determine instructor
    // ----------------------------------------------

    let instructorId;


    if (session.role === "instructor") {

        // Instructor creates exam for himself

        instructorId =
            session.userId;

    } else {

        // Admin must provide instructorId

        instructorId =
            normalizeText(body.instructorId);


        if (
            !instructorId ||
            !isValidObjectId(instructorId)
        ) {

            return sendJson(res, 400, {
                error: "Invalid instructorId"
            });
        }
    }


    // ----------------------------------------------
    // Check instructor exists
    // ----------------------------------------------

    const instructor =
        await db.collection("users").findOne({

            _id:
                new ObjectId(instructorId),

            role: "instructor"
        });


    if (!instructor) {

        return sendJson(res, 404, {
            error: "Instructor not found"
        });
    }


    // ----------------------------------------------
    // Check schedule conflict
    // ----------------------------------------------

    const conflict =
        await db.collection("exams").findOne({

            instructorId:
                instructor._id,

            scheduledAt:
                examDate
        });


    if (conflict) {

        return sendJson(res, 409, {
            error:
                "Instructor already has an exam at this time"
        });
    }


    // ----------------------------------------------
    // Create exam
    // ----------------------------------------------

    const exam = {

        title: title,

        subjectCode: subjectCode,

        durationMinutes:
            durationMinutes,

        totalMarks:
            totalMarks,

        scheduledAt:
            examDate,

        instructorId:
            instructor._id,

        instructorName:
            instructor.name,

        status:
            "scheduled",

        createdAt:
            new Date(),

        updatedAt:
            new Date()
    };


    const result =
        await db.collection("exams")
            .insertOne(exam);


    return sendJson(res, 201, {

        message:
            "Exam created",

        examId:
            result.insertedId
    });
}


// ==================================================
// Route 8
// GET /exams
// Student + Admin
// ==================================================

async function getExams(req, res) {

    const session = requireRole(
        req,
        res,
        ["student", "admin"]
    );


    if (!session) {
        return;
    }


    const db = getDB();


    const query = {};


    // ----------------------------------------------
    // Student filtering
    // ----------------------------------------------

    if (session.role === "student") {

        query.status = "scheduled";

        query.scheduledAt = {
            $gte: new Date()
        };
    }


    // ----------------------------------------------
    // Subject filter
    // ----------------------------------------------

    const subject =
        req.parsedUrl.searchParams
            .get("subject");


    if (subject) {

        query.subjectCode =
            subject;
    }


    // ----------------------------------------------
    // From filter
    // ----------------------------------------------

    const from =
        req.parsedUrl.searchParams
            .get("from");


    if (from) {

        const fromDate =
            new Date(from);


        if (Number.isNaN(fromDate.getTime())) {

            return sendJson(res, 400, {
                error: "Invalid from date"
            });
        }


        if (!query.scheduledAt) {

            query.scheduledAt = {};
        }


        if (session.role === "student") {

            const now = new Date();


            query.scheduledAt.$gte =
                fromDate > now
                    ? fromDate
                    : now;

        } else {

            query.scheduledAt.$gte =
                fromDate;
        }
    }


    // ----------------------------------------------
    // To filter
    // ----------------------------------------------

    const to =
        req.parsedUrl.searchParams
            .get("to");


    if (to) {

        const toDate =
            new Date(to);


        if (Number.isNaN(toDate.getTime())) {

            return sendJson(res, 400, {
                error: "Invalid to date"
            });
        }


        toDate.setHours(
            23,
            59,
            59,
            999
        );


        if (!query.scheduledAt) {

            query.scheduledAt = {};
        }


        query.scheduledAt.$lte =
            toDate;
    }


    // ----------------------------------------------
    // Student result
    // ----------------------------------------------

    if (session.role === "student") {

        const exams =
            await db.collection("exams")
                .find(query)
                .project({
                    _id: 0,
                    title: 1,
                    subjectCode: 1,
                    durationMinutes: 1,
                    totalMarks: 1,
                    scheduledAt: 1,
                    instructorName: 1,
                    status: 1
                })
                .sort({
                    scheduledAt: 1,
                    subjectCode: 1
                })
                .toArray();


        return sendJson(res, 200, exams);
    }


    // ----------------------------------------------
    // Admin result
    // ----------------------------------------------

    const exams =
        await db.collection("exams")
            .find(query)
            .sort({
                scheduledAt: 1
            })
            .toArray();


    return sendJson(res, 200, exams);
}


// ==================================================
// Route 9
// PUT /exams/:examId
// Instructor + Admin
// ==================================================

async function updateExam(req, res, examId) {

    // ----------------------------------------------
    // Validate examId
    // ----------------------------------------------

    if (!isValidObjectId(examId)) {

        return sendJson(res, 400, {
            error: "Invalid exam ID"
        });
    }


    // ----------------------------------------------
    // Check role
    // ----------------------------------------------

    const session = requireRole(
        req,
        res,
        ["instructor", "admin"]
    );


    if (!session) {
        return;
    }


    const body =
        await readJson(req);


    const db = getDB();


    const updateFields = {};


    // ----------------------------------------------
    // Title
    // ----------------------------------------------

    if (
        Object.prototype.hasOwnProperty.call(
            body,
            "title"
        )
    ) {

        const title =
            normalizeText(body.title);


        if (!title) {

            return sendJson(res, 400, {
                error:
                    "title cannot be empty"
            });
        }


        updateFields.title =
            title;
    }


    // ----------------------------------------------
    // Subject code
    // ----------------------------------------------

    if (
        Object.prototype.hasOwnProperty.call(
            body,
            "subjectCode"
        )
    ) {

        const subjectCode =
            normalizeText(body.subjectCode);


        if (!subjectCode) {

            return sendJson(res, 400, {
                error:
                    "subjectCode cannot be empty"
            });
        }


        const subject =
            await db.collection("subjects")
                .findOne({
                    code:
                        subjectCode
                });


        if (!subject) {

            return sendJson(res, 400, {
                error:
                    "Subject not found"
            });
        }


        updateFields.subjectCode =
            subjectCode;
    }


    // ----------------------------------------------
    // Duration
    // ----------------------------------------------

    if (
        Object.prototype.hasOwnProperty.call(
            body,
            "durationMinutes"
        )
    ) {

        if (
            !Number.isInteger(
                body.durationMinutes
            ) ||
            body.durationMinutes <= 0
        ) {

            return sendJson(res, 400, {
                error:
                    "durationMinutes must be a positive integer"
            });
        }


        updateFields.durationMinutes =
            body.durationMinutes;
    }


    // ----------------------------------------------
    // Total marks
    // ----------------------------------------------

    if (
        Object.prototype.hasOwnProperty.call(
            body,
            "totalMarks"
        )
    ) {

        if (
            typeof body.totalMarks !== "number" ||
            body.totalMarks <= 0
        ) {

            return sendJson(res, 400, {
                error:
                    "totalMarks must be greater than 0"
            });
        }


        updateFields.totalMarks =
            body.totalMarks;
    }


    // ----------------------------------------------
    // scheduledAt
    // ----------------------------------------------

    let newScheduledAt = null;


    if (
        Object.prototype.hasOwnProperty.call(
            body,
            "scheduledAt"
        )
    ) {

        newScheduledAt =
            new Date(body.scheduledAt);


        if (
            Number.isNaN(
                newScheduledAt.getTime()
            ) ||
            newScheduledAt <= new Date()
        ) {

            return sendJson(res, 400, {
                error:
                    "scheduledAt must be a valid future date/time"
            });
        }


        updateFields.scheduledAt =
            newScheduledAt;
    }


    // ----------------------------------------------
    // At least one field
    // ----------------------------------------------

    if (
        Object.keys(updateFields).length === 0
    ) {

        return sendJson(res, 400, {
            error:
                "At least one valid field is required"
        });
    }


    // ==================================================
    // Instructor
    // ==================================================

    if (session.role === "instructor") {

        const instructorId =
            new ObjectId(
                session.userId
            );


        // ------------------------------------------
        // Check ownership + future
        // ------------------------------------------

        const currentExam =
            await db.collection("exams")
                .findOne({

                    _id:
                        new ObjectId(examId),

                    instructorId:
                        instructorId,

                    scheduledAt: {
                        $gt:
                            new Date()
                    }
                });


        if (!currentExam) {

            return sendJson(res, 404, {
                error:
                    "Exam not found"
            });
        }


        // ------------------------------------------
        // Schedule conflict
        // ------------------------------------------

        if (newScheduledAt) {

            const conflict =
                await db.collection("exams")
                    .findOne({

                        instructorId:
                            instructorId,

                        scheduledAt:
                            newScheduledAt,

                        _id: {
                            $ne:
                                new ObjectId(examId)
                        }
                    });


            if (conflict) {

                return sendJson(res, 409, {
                    error:
                        "Instructor already has an exam at this time"
                });
            }
        }


        // ------------------------------------------
        // Update own future exam
        // ------------------------------------------

        const result =
            await db.collection("exams")
                .updateOne(

                    {
                        _id:
                            new ObjectId(examId),

                        instructorId:
                            instructorId,

                        scheduledAt: {
                            $gt:
                                new Date()
                        }
                    },

                    {
                        $set:
                            updateFields
                    }
                );


        if (result.matchedCount === 0) {

            return sendJson(res, 404, {
                error:
                    "Exam not found"
            });
        }


        return sendJson(res, 200, {
            message:
                "Exam updated"
        });
    }


    // ==================================================
    // Admin
    // ==================================================

    if (newScheduledAt) {

        const currentExam =
            await db.collection("exams")
                .findOne({

                    _id:
                        new ObjectId(examId)
                });


        if (!currentExam) {

            return sendJson(res, 404, {
                error:
                    "Exam not found"
            });
        }


        // ------------------------------------------
        // Check schedule conflict
        // ------------------------------------------

        const conflict =
            await db.collection("exams")
                .findOne({

                    instructorId:
                        currentExam.instructorId,

                    scheduledAt:
                        newScheduledAt,

                    _id: {
                        $ne:
                            new ObjectId(examId)
                    }
                });


        if (conflict) {

            return sendJson(res, 409, {
                error:
                    "Instructor already has an exam at this time"
            });
        }
    }


    // ----------------------------------------------
    // Admin update
    // ----------------------------------------------

    const result =
        await db.collection("exams")
            .updateOne(

                {
                    _id:
                        new ObjectId(examId)
                },

                {
                    $set:
                        updateFields
                }
            );


    if (result.matchedCount === 0) {

        return sendJson(res, 404, {
            error:
                "Exam not found"
        });
    }


    return sendJson(res, 200, {
        message:
            "Exam updated"
    });
}


// ==================================================
// Route 10
// DELETE /exams/:examId
// Admin only
// ==================================================

async function deleteExam(req, res, examId) {

    // ----------------------------------------------
    // Validate ID
    // ----------------------------------------------

    if (!isValidObjectId(examId)) {

        return sendJson(res, 400, {
            error:
                "Invalid exam ID"
        });
    }


    // ----------------------------------------------
    // Admin only
    // ----------------------------------------------

    const session = requireRole(
        req,
        res,
        ["admin"]
    );


    if (!session) {
        return;
    }


    const db = getDB();


    const result =
        await db.collection("exams")
            .deleteOne({

                _id:
                    new ObjectId(examId)
            });


    if (result.deletedCount === 0) {

        return sendJson(res, 404, {
            error:
                "Exam not found"
        });
    }


    return sendJson(res, 200, {
        message:
            "Exam deleted"
    });
}


// ==================================================
// SERVER
// ==================================================

const server =
    http.createServer(async (req, res) => {
            try {
                const origin =req.headers.origin;
                if (origin && !allowedOrigins.has(origin)) {
                    sendJson(res, 403, {error:"CORS origin not allowed"});
                    return;
                }
                applyCors(req, res);
                if (req.method === "OPTIONS") {
                    res.writeHead(204);
                    res.end();
                    return;
                }
                const parsedUrl =new URL(req.url,`http://${req.headers.host}`);
                req.parsedUrl =parsedUrl;

                const pathname =parsedUrl.pathname;

                if (
                    req.method === "POST" &&
                    pathname === "/login"
                ) {

                    return login(req, res);
                }


                // ==================================================
                // Route 2 - Logout
                // ==================================================

                if (
                    req.method === "POST" &&
                    pathname === "/logout"
                ) {

                    return logout(req, res);
                }


                // ==================================================
                // Route 3 - Health
                // ==================================================

                if (
                    req.method === "GET" &&
                    pathname === "/health"
                ) {

                    return health(req, res);
                }


                // ==================================================
                // Route 4 - Session
                // ==================================================

                if (
                    req.method === "GET" &&
                    pathname === "/session"
                ) {

                    return getSessionInfo(
                        req,
                        res
                    );
                }


                // ==================================================
                // Route 5 - Subjects
                // ==================================================

                if (
                    req.method === "GET" &&
                    pathname === "/subjects"
                ) {

                    return getSubjects(
                        req,
                        res
                    );
                }


                // ==================================================
                // Route 6 - Instructors
                // ==================================================

                if (
                    req.method === "GET" &&
                    pathname === "/instructors"
                ) {

                    return getInstructors(
                        req,
                        res
                    );
                }


                // ==================================================
                // Route 7 - Create Exam
                // ==================================================

                if (
                    req.method === "POST" &&
                    pathname === "/exams"
                ) {

                    return createExam(
                        req,
                        res
                    );
                }


                // ==================================================
                // Route 8 - Get Exams
                // ==================================================

                if (
                    req.method === "GET" &&
                    pathname === "/exams"
                ) {

                    return getExams(
                        req,
                        res
                    );
                }


                // ==================================================
                // Dynamic Exam Routes
                // ==================================================

                const examMatch =
                    pathname.match(
                        /^\/exams\/([^/]+)$/
                    );


                if (examMatch) {

                    const examId =
                        examMatch[1];


                    // ------------------------------------------
                    // Route 9 - Update Exam
                    // ------------------------------------------

                    if (
                        req.method === "PUT"
                    ) {

                        return updateExam(
                            req,
                            res,
                            examId
                        );
                    }


                    // ------------------------------------------
                    // Route 10 - Delete Exam
                    // ------------------------------------------

                    if (
                        req.method === "DELETE"
                    ) {

                        return deleteExam(
                            req,
                            res,
                            examId
                        );
                    }
                }


                // ----------------------------------
                // No route matched
                // ----------------------------------

                return sendJson(res, 404, {
                    error:
                        "Route not found"
                });

            }

            catch (err) {

                console.error(err);

                return sendJson(res, 500, {
                    error:
                        "Internal server error"
                });
            }
        }
    );


// ==================================================
// DATABASE CONNECTION + SERVER START
// ==================================================

async function startServer() {
    try {
        await connectDB();
        const db = getDB();
        server.listen(PORT,() => {
                console.log(`Server running on http://localhost:${PORT}`);
            }
        );
    }
    catch (err) {
        console.log("Failed to start server:",err);
    }
}
startServer();


Health care

require('dotenv').config();

const http = require('http');
const { URL } = require('url');
const { ObjectId } = require('mongodb');
const { connectDB, getDB, closeDB } = require('./db');
const {
  sendJson,
  readJson,
  hashToken,
  verifyPassword
} = require('./utils');
const {
  createSession,
  sessionCookie,
  clearSessionCookie,
  getAuthenticatedUser,
  requireRole
} = require('./auth');

const PORT = Number(process.env.PORT || 3000);
const allowedOrigins = new Set(
  String(process.env.ALLOWED_ORIGINS || '')
    .split(',')
    .map(v => v.trim())
    .filter(Boolean)
);

function applyCors(req, res) {
  const origin = req.headers.origin;

  if (origin && allowedOrigins.has(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Access-Control-Allow-Credentials', 'true');
    res.setHeader('Vary', 'Origin');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  }
}

function isValidObjectId(value) {
  return ObjectId.isValid(value) && String(new ObjectId(value)) === value;
}

async function login(req, res) {
  const { email, password } = await readJson(req);
  if (!email || !password) {
    return sendJson(res, 400, { error: 'email and password are required' });
  }

  const db = getDB();
  const user = await db.collection('users').findOne({ email: email.toLowerCase() });
  if (!user || !verifyPassword(password, user.passwordHash)) {
    return sendJson(res, 401, { error: 'Invalid credentials' });
  }

  const { rawToken, expiresAt } = await createSession(user);
  return sendJson(
    res,
    200,
    { message: 'Login successful', user: { id: user._id, name: user.name, role: user.role } },
    { 'Set-Cookie': sessionCookie(rawToken, expiresAt) }
  );
}

async function logout(req, res, user) {
  if (user?.sessionTokenHash) {
    await db.collection('sessions').deleteOne({ tokenHash: user.sessionTokenHash });
  }
  return sendJson(res, 200, { message: 'Logged out' }, { 'Set-Cookie': clearSessionCookie() });
}

async function registerAppointment(req, res, user) {
  if (!requireRole(user, ['patient'])) {
    return sendJson(res, 403, { error: 'Only patients can register appointments' });
  }

  const { doctorId, appointmentAt, reason } = await readJson(req);
  if (!doctorId || !appointmentAt || !reason) {
    return sendJson(res, 400, { error: 'doctorId, appointmentAt and reason are required' });
  }
  if (!isValidObjectId(doctorId)) {
    return sendJson(res, 400, { error: 'Invalid doctorId' });
  }

  const appointmentDate = new Date(appointmentAt);
  if (Number.isNaN(appointmentDate.getTime())) {
    return sendJson(res, 400, { error: 'appointmentAt must be a valid ISO date/time' });
  }

  const db = getDB();
  const doctor = await db.collection('users').findOne({ _id: new ObjectId(doctorId), role: 'doctor' });
  if (!doctor) return sendJson(res, 404, { error: 'Doctor not found' });

  const overlapping = await db.collection('appointments').findOne({
    doctorId: doctor._id,
    appointmentAt: appointmentDate,
    status: { $in: ['scheduled', 'confirmed'] }
  });
  if (overlapping) {
    return sendJson(res, 409, { error: 'Doctor already has an appointment at that time' });
  }

  const appointment = {
    patientId: user._id,
    doctorId: doctor._id,
    appointmentAt: appointmentDate,
    reason,
    status: 'scheduled',
    consultationFee: Number(doctor.consultationFee || 0),
    createdAt: new Date()
  };

  const result = await db.collection('appointments').insertOne(appointment);
  return sendJson(res, 201, {
    message: 'Appointment registered',
    appointmentId: result.insertedId,
    appointment: { ...appointment, doctorName: doctor.name }
  });
}

async function listMyAppointments(req, res, user) {
  if (!requireRole(user, ['patient', 'doctor'])) {
    return sendJson(res, 403, { error: 'Patients and doctors only' });
  }

  const db = getDB();
  const match = user.role === 'patient' ? { patientId: user._id } : { doctorId: user._id };
  const appointments = await db.collection('appointments').aggregate([
    { $match: match },
    { $sort: { appointmentAt: -1 } },
    {
      $lookup: {
        from: 'users',
        localField: user.role === 'patient' ? 'doctorId' : 'patientId',
        foreignField: '_id',
        as: 'counterparty'
      }
    },
    { $unwind: { path: '$counterparty', preserveNullAndEmptyArrays: true } },
    {
      $project: {
        patientId: 1,
        doctorId: 1,
        appointmentAt: 1,
        reason: 1,
        status: 1,
        consultationFee: 1,
        counterpartyName: '$counterparty.name'
      }
    }
  ]).toArray();

  return sendJson(res, 200, { appointments });
}

async function getPatientBill(req, res, user, patientId) {
  if (!requireRole(user, ['patient', 'doctor', 'pharmacist'])) {
    return sendJson(res, 403, { error: 'Not authorized' });
  }
  if (!isValidObjectId(patientId)) {
    return sendJson(res, 400, { error: 'Invalid patientId' });
  }

  const requestedPatientId = new ObjectId(patientId);
  if (user.role === 'patient' && !user._id.equals(requestedPatientId)) {
    return sendJson(res, 403, { error: 'Patients can view only their own bill' });
  }

  const db = getDB();
  const patient = await db.collection('users').findOne(
    { _id: requestedPatientId, role: 'patient' },
    { projection: { passwordHash: 0 } }
  );
  if (!patient) return sendJson(res, 404, { error: 'Patient not found' });

  // Core MongoDB aggregation: sum every line item across all bills for one patient.
  const result = await db.collection('bills').aggregate([
    { $match: { patientId: requestedPatientId } },
    { $unwind: '$items' },
    {
      $group: {
        _id: '$patientId',
        grossAmount: { $sum: '$items.amount' },
        totalPaid: {
          $sum: {
            $cond: [{ $eq: ['$status', 'paid'] }, '$items.amount', 0]
          }
        },
        itemCount: { $sum: 1 },
        billIds: { $addToSet: '$_id' }
      }
    },
    {
      $addFields: {
        outstandingAmount: { $subtract: ['$grossAmount', '$totalPaid'] },
        billCount: { $size: '$billIds' }
      }
    },
    { $project: { billIds: 0 } }
  ]).toArray();

  const summary = result[0] || {
    _id: requestedPatientId,
    grossAmount: 0,
    totalPaid: 0,
    outstandingAmount: 0,
    itemCount: 0,
    billCount: 0
  };

  return sendJson(res, 200, {
    patient: { id: patient._id, name: patient.name, email: patient.email },
    billSummary: summary
  });
}

async function createBill(req, res, user) {
  if (!requireRole(user, ['doctor', 'pharmacist'])) {
    return sendJson(res, 403, { error: 'Only doctors and pharmacists can create bill entries' });
  }

  const { patientId, items, status = 'unpaid' } = await readJson(req);
  if (!isValidObjectId(patientId) || !Array.isArray(items) || items.length === 0) {
    return sendJson(res, 400, { error: 'Valid pati     entId and non-empty items[] are required' });
  }
  if (!['paid', 'unpaid'].includes(status)) {
    return sendJson(res, 400, { error: 'status must be paid or unpaid' });
  }

  const normalizedItems = items.map(item => ({
    description: String(item.description || '').trim(),
    amount: Number(item.amount)
  }));
  if (normalizedItems.some(item => !item.description || !Number.isFinite(item.amount) || item.amount < 0)) {
    return sendJson(res, 400, { error: 'Each item needs description and non-negative numeric amount' });
  }

  const db = getDB();
  const pid = new ObjectId(patientId);
  const patient = await db.collection('users').findOne({ _id: pid, role: 'patient' });
  if (!patient) return sendJson(res, 404, { error: 'Patient not found' });

  const bill = {
    patientId: pid,
    createdBy: user._id,
    createdByRole: user.role,
    items: normalizedItems,
    status,
    createdAt: new Date()
  };
  const result = await db.collection('bills').insertOne(bill);

  return sendJson(res, 201, { message: 'Bill entry created', billId: result.insertedId, bill });
}

async function route(req, res) {
  applyCors(req, res);

  if (req.method === 'OPTIONS') {
    const origin = req.headers.origin;
    if (origin && !allowedOrigins.has(origin)) {
      return sendJson(res, 403, { error: 'Origin not allowed by CORS policy' });
    }
    res.writeHead(204);
    return res.end();
  }

  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

  if (req.method === 'GET' && url.pathname === '/health') {
    return sendJson(res, 200, { ok: true, service: 'healthcare-backend' });
  }

  if (req.method === 'POST' && url.pathname === '/auth/login') {
    return login(req, res);
  }

  const user = await getAuthenticatedUser(req);
  if (!user) return sendJson(res, 401, { error: 'Authentication required' });

  if (req.method === 'POST' && url.pathname === '/auth/logout') {
    return logout(req, res, user);
  }

  if (req.method === 'GET' && url.pathname === '/auth/me') {
    return sendJson(res, 200, { user: { id: user._id, name: user.name, email: user.email, role: user.role } });
  }

  if (req.method === 'POST' && url.pathname === '/appointments') {
    return registerAppointment(req, res, user);
  }

  if (req.method === 'GET' && url.pathname === '/appointments/me') {
    return listMyAppointments(req, res, user);
  }

  if (req.method === 'POST' && url.pathname === '/bills') {
    return createBill(req, res, user);
  }

  const billMatch = url.pathname.match(/^\/patients\/([a-fA-F0-9]{24})\/bill$/);
  if (req.method === 'GET' && billMatch) {
    return getPatientBill(req, res, user, billMatch[1]);
  }

  return sendJson(res, 404, { error: 'Route not found' });
}

async function start() {
  await connectDB();
  const server = http.createServer((req, res) => {
    route(req, res).catch(err => {
      console.error(err);
      if (!res.headersSent) sendJson(res, 500, { error: 'Internal server error' });
      else res.end();
    });
  });

  server.listen(PORT, () => {
    console.log(`Healthcare backend running on http://localhost:${PORT}`);
  });

  const shutdown = async () => {
    server.close(async () => {
      await closeDB();
      process.exit(0);
    });
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

start().catch(err => {
  console.error('Startup failed:', err);
  process.exit(1);
});
