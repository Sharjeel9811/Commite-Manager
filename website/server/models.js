import mongoose from 'mongoose'

const memberSchema = new mongoose.Schema({ name: String, turn: Number, paid: Number, due: Number, status: String }, { _id: false })
export const Committee = mongoose.model('Committee', new mongoose.Schema({
  name: String, contribution: Number, members: Number, collected: Number, target: Number, status: String, nextPayout: String, accent: String, roster: [memberSchema]
}, { timestamps: true }))

export const Payment = mongoose.model('Payment', new mongoose.Schema({
  member: String, committee: String, amount: Number, date: String, status: String
}, { timestamps: true }))
