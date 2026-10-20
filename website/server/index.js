import 'dotenv/config'
import express from 'express'
import cors from 'cors'
import mongoose from 'mongoose'
import { Committee, Payment } from './models.js'

const app = express()
app.use(cors())
app.use(express.json())

const demoCommittees = [
  { name: 'Family Circle', contribution: 5000, members: 16, collected: 560000, target: 800000, status: 'Active', nextPayout: 'Jun 15, 2026', accent: 'indigo', roster: ['Sidra', 'Hassan', 'Rozi', 'Falak', 'Anaya'].map((name, i) => ({ name, turn: i + 1, paid: i < 3 ? 12 : 10, due: 16, status: i < 3 ? 'Paid' : 'Due' })) },
  { name: 'Friends Savings', contribution: 3000, members: 10, collected: 180000, target: 300000, status: 'Active', nextPayout: 'Jun 28, 2026', accent: 'mint', roster: ['Qasim', 'Hiba', 'Eshaal'].map((name, i) => ({ name, turn: i + 1, paid: 8, due: 10, status: i === 0 ? 'Paid' : 'Due' })) },
  { name: 'Office Committee', contribution: 10000, members: 8, collected: 320000, target: 640000, status: 'Active', nextPayout: 'Jul 04, 2026', accent: 'coral', roster: ['Adeel', 'Maham', 'Sana'].map((name, i) => ({ name, turn: i + 1, paid: 5, due: 8, status: 'Due' })) }
]

const mongoConnection = process.env.MONGODB_URI
  ? mongoose.connect(process.env.MONGODB_URI).catch((error) => {
      console.error('MongoDB connection failed:', error.message)
      return null
    })
  : Promise.resolve(null)

const isMongoReady = async () => {
  if (mongoose.connection.readyState === 1) return true
  await mongoConnection
  return mongoose.connection.readyState === 1
}

app.get('/api/health', async (_req, res) => res.json({ ok: true, database: (await isMongoReady()) ? 'connected' : 'demo' }))
app.get('/api/committees', async (_req, res) => {
  const data = (await isMongoReady()) ? await Committee.find().lean() : demoCommittees
  res.json(data)
})
app.post('/api/committees', async (req, res) => {
  const committee = { ...req.body, status: 'Active', collected: 0, roster: [] }
  if (await isMongoReady()) return res.status(201).json(await Committee.create(committee))
  demoCommittees.push(committee)
  res.status(201).json(committee)
})
app.get('/api/payments', async (_req, res) => {
  const data = (await isMongoReady()) ? await Payment.find().sort({ createdAt: -1 }).limit(20).lean() : [
    { member: 'Sidra Khan', committee: 'Family Circle', amount: 5000, date: 'Today, 10:24 AM', status: 'Received' },
    { member: 'Hassan Raza', committee: 'Family Circle', amount: 5000, date: 'Yesterday', status: 'Received' },
    { member: 'Qasim Ali', committee: 'Friends Savings', amount: 3000, date: 'Jun 08, 2026', status: 'Received' }
  ]
  res.json(data)
})

if (process.env.NODE_ENV !== 'production') {
  const port = process.env.PORT || 5000
  app.listen(port, () => console.log(`API running on port ${port}`))
}

export default app
